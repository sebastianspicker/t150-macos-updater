/* Native transport for the exact reviewed T150 bootloader. Memory reads use
 * 40/47; programming uses40/0d, raw bulk OUT, then40/01 write-disable. Flash is
 * changed during bulk transfer. No reset or mode switch is implemented here.
 */
#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>

static uint64_t bound_registry;
static int expected_application = -1, observed_application = -1, observed_bootloader = -1;
static int transport_quarantined;
static volatile sig_atomic_t interrupted;
static void interrupt_operation(int signal_number) { (void)signal_number; interrupted = 1; }

#define IMAGE_SIZE 65536
#define BLOCK_SIZE 32
#define BLOCKS (IMAGE_SIZE / BLOCK_SIZE)

static uint64_t monotonic_nanoseconds(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

typedef struct {
    unsigned char image[IMAGE_SIZE], seen[BLOCKS], packet[64];
    unsigned count, packets, duplicates, tag, padded_frames;
    unsigned stale_partial_frames;
    const unsigned char *expected_partial_image;
    int error, pending, stopping;
    IOUSBInterfaceInterface300 **interface;
    UInt8 input_pipe;
} Reader;

static int valid_partial(const unsigned char *data, size_t size, const unsigned char *expected) {
    if (!expected || (size != 35 && size != 36) || data[0] != 4 ||
        (size == 36 && data[35] != 0)) return 0;
    unsigned next = data[1] | ((unsigned)data[2] << 8);
    if (!next) next = IMAGE_SIZE; /* Final 16-bit next address wraps at 64KiB. */
    if (next < 0x2100 || next > IMAGE_SIZE || next % 256) return 0;
    return !memcmp(data + 3, expected + next - 256, BLOCK_SIZE);
}

static int accept_packet(Reader *reader, const unsigned char *data, size_t size) {
    if (size && data[0] == 4 && reader->expected_partial_image) {
        if (!valid_partial(data, size, reader->expected_partial_image)) return 1;
        ++reader->stale_partial_frames;
        return 0; /* Never counts toward full tag-3 coverage. */
    }
    /* Vendor parser uses only tag/address + 32 data bytes; hardware emits a
     * 36-byte aligned frame with one zero pad byte. Accept only that confirmed padding
     * and the unpadded 35-byte form, never arbitrary trailing data.
     */
    if ((size != 35 && size != 36) || (size == 36 && data[35] != 0) ||
        data[0] != 3) return 1;
    unsigned address = data[1] | ((unsigned)data[2] << 8);
    if (address % BLOCK_SIZE || address > IMAGE_SIZE - BLOCK_SIZE) return 1;
    if (reader->tag && reader->tag != data[0]) return 1;
    reader->tag = data[0];
    if (size == 36) ++reader->padded_frames;
    unsigned block = address / BLOCK_SIZE;
    if (reader->seen[block]) {
        if (memcmp(reader->image + address, data + 3, BLOCK_SIZE)) return 1;
        ++reader->duplicates;
        return 0;
    }
    memcpy(reader->image + address, data + 3, BLOCK_SIZE);
    reader->seen[block] = 1;
    ++reader->count;
    return 0;
}

static int complete_image(const Reader *reader) {
    if (reader->error || reader->count != BLOCKS || reader->tag != 3) return 0;
    for (unsigned i = 0; i < BLOCKS; ++i) if (!reader->seen[i]) return 0;
    return 1;
}

static void received(void *reference, IOReturn result, void *argument) {
    Reader *reader = reference;
    reader->pending = 0;
    if (reader->stopping) return;
    size_t size = (size_t)(uintptr_t)argument;
    ++reader->packets;
    if (result || reader->packets > BLOCKS * 2 || accept_packet(reader, reader->packet, size)) {
        fprintf(stderr, "Read frame rejected: result=0x%08x size=%zu frame=%u\n", result, size, reader->packets);
        fprintf(stderr, "rejected_frame_hex=");
        size_t available = size < sizeof(reader->packet) ? size : sizeof(reader->packet);
        for (size_t i = 0; i < available; ++i) fprintf(stderr, "%02x", reader->packet[i]);
        fprintf(stderr, "\n");
        reader->error = 1;
        return;
    }
    if (reader->count == BLOCKS) return;
    result = (*reader->interface)->ReadPipeAsync(reader->interface, reader->input_pipe,
        reader->packet, sizeof(reader->packet), received, reader);
    if (result) reader->error = 1;
    else reader->pending = 1;
}

static unsigned property(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    int result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue(value, kCFNumberIntType, &result);
    if (value) CFRelease(value);
    return (unsigned)result;
}

static int versions_match(IOUSBDeviceInterface **device, int application_version) {
    for (unsigned code = 2; code <= 3; ++code) {
        unsigned char data[2] = {0};
        IOUSBDevRequestTO request = {0};
        request.noDataTimeout = 1000; request.completionTimeout = 1000;
        request.bmRequestType = 0xc0;
        request.bRequest = (UInt8)code;
        request.wLength = 2;
        request.pData = data;
        IOReturn result = (*device)->DeviceRequestTO(device, &request);
        printf("identity_read=c0/%02x result=0x%08x bytes=%u response=%02x%02x\n",
               code, result, (unsigned)request.wLenDone, data[0], data[1]);
        if (result || request.wLenDone != 2) return 0;
        unsigned value = data[0] | ((unsigned)data[1] << 8);
        if (code == 2) observed_application = (int)value;
        else observed_bootloader = (int)value;
        if ((code == 3 && value != 5) || (code == 2 && application_version >= 0 && value != (unsigned)application_version)) return 0;
    }
    return 1;
}

static int descriptor_matches(IOUSBDeviceInterface **device) {
    static const unsigned char expected[] = {
        9,2,32,0,1,1,0,0x80,0x19, 9,4,0,0,2,0xff,0,0,0,
        7,5,0x81,3,64,0,1, 7,5,1,2,64,0,1
    };
    unsigned char data[sizeof(expected)] = {0};
    IOUSBDevRequestTO request = {0};
        request.noDataTimeout = 1000; request.completionTimeout = 1000;
    request.bmRequestType = 0x80;
    request.bRequest = 6;
    request.wValue = 0x0200;
    request.wLength = sizeof(data);
    request.pData = data;
    IOReturn result = (*device)->DeviceRequestTO(device, &request);
    printf("descriptor_guard_result=0x%08x bytes=%u\n", result, (unsigned)request.wLenDone);
    return !result && request.wLenDone == sizeof(expected) && !memcmp(data, expected, sizeof(expected));
}

#define T150_PAGE_SIZE 4096
typedef struct { unsigned address, length; } Run;
typedef struct {
    IOUSBDeviceInterface **device;
    IOUSBInterfaceInterface300 **interface;
    CFRunLoopSourceRef source;
    UInt8 input, output;
    unsigned char packet[64];
    const unsigned char *target;
    int device_open, interface_open, read_pending, write_pending, stopping, error;
    IOReturn write_result;
    size_t written;
    unsigned partial_frames;
} ProgramSession;

static unsigned make_runs(const unsigned char *before, const unsigned char *target, Run runs[14]) {
    unsigned count = 0;
    for (unsigned address = 0x2000; address < IMAGE_SIZE; address += T150_PAGE_SIZE) {
        if (!memcmp(before + address, target + address, T150_PAGE_SIZE)) continue;
        if (count && runs[count - 1].address + runs[count - 1].length == address)
            runs[count - 1].length += T150_PAGE_SIZE;
        else { runs[count].address = address; runs[count].length = T150_PAGE_SIZE; ++count; }
    }
    return count;
}

static void telemetry(void *reference, IOReturn result, void *argument) {
    ProgramSession *session = reference;
    session->read_pending = 0;
    if (session->stopping) return;
    size_t size = (size_t)(uintptr_t)argument;
    if (result || !valid_partial(session->packet, size, session->target) || ++session->partial_frames > 4096) {
        fprintf(stderr, "Partial-check telemetry rejected result=0x%08x bytes=%zu\n", result, size);
        fprintf(stderr, "partial_frame_hex=");
        for (size_t i = 0; i < size && i < sizeof(session->packet); ++i) fprintf(stderr, "%02x", session->packet[i]);
        fprintf(stderr, "\n");
        session->error = 1;
        return;
    }
    result = (*session->interface)->ReadPipeAsync(session->interface, session->input,
        session->packet, sizeof(session->packet), telemetry, session);
    if (result) session->error = 1;
    else session->read_pending = 1;
}

static void write_completed(void *reference, IOReturn result, void *argument) {
    ProgramSession *session = reference;
    session->write_result = result;
    session->written = (size_t)(uintptr_t)argument;
    session->write_pending = 0;
}

/* The one path that finds, identifies and opens the bootloader, for backup reads and
 * for programming. It sends only IN control requests (versions, descriptor), never an OUT. */
static int open_bootloader(ProgramSession *session, int application_version) {
    if (transport_quarantined || interrupted || !bound_registry) return 1;
    io_iterator_t devices = IO_OBJECT_NULL, interfaces = IO_OBJECT_NULL;
    io_service_t service, target = IO_OBJECT_NULL, interface_service = IO_OBJECT_NULL;
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    int status = 1;
    IOReturn result = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching(kIOUSBDeviceClassName), &devices);
    if (result) { fprintf(stderr, "USB enumeration failed\n"); goto cleanup; }
    unsigned count = 0;
    while ((service = IOIteratorNext(devices))) {
        if (property(service, CFSTR("idVendor")) == 0x044f) {
            ++count;
            if (!target && property(service, CFSTR("idProduct")) == 0xb676) {
                IOObjectRetain(service); target = service;
            }
        }
        IOObjectRelease(service);
    }
    if (count != 1 || !target) { fprintf(stderr, "Require exactly one Thrustmaster device, PID b676.\n"); goto cleanup; }
    uint64_t registry = 0;
    if (IORegistryEntryGetRegistryEntryID(target, &registry) || registry != bound_registry) goto cleanup;
    result = IOCreatePlugInInterfaceForService(target, kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    if (result || !plugin) { fprintf(stderr, "USB client failed 0x%08x\n", result); goto cleanup; }
    /* DeviceRequestTO is present from v182 onward; explicitly request v320.
     * Only its compatible prefix methods are used via the current SDK alias. */
    HRESULT queried = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID *)&session->device);
    IODestroyPlugInInterface(plugin); plugin = NULL;
    if (queried || !session->device) goto cleanup;
    result = (*session->device)->USBDeviceOpen(session->device);
    if (result) { fprintf(stderr, "USB open failed 0x%08x\n", result); goto cleanup; }
    session->device_open = 1;
    if (!versions_match(session->device, application_version) || !descriptor_matches(session->device)) goto cleanup;
    IOUSBFindInterfaceRequest find = {kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare};
    result = (*session->device)->CreateInterfaceIterator(session->device, &find, &interfaces);
    if (result) goto cleanup;
    interface_service = IOIteratorNext(interfaces);
    if (!interface_service) goto cleanup;
    service = IOIteratorNext(interfaces);
    if (service) { IOObjectRelease(service); fprintf(stderr, "Unexpected extra USB interface.\n"); goto cleanup; }
    result = IOCreatePlugInInterfaceForService(interface_service, kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    if (result || !plugin) goto cleanup;
    queried = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&session->interface);
    IODestroyPlugInInterface(plugin); plugin = NULL;
    if (queried || !session->interface) goto cleanup;
    result = (*session->interface)->USBInterfaceOpen(session->interface); /* Ordinary open; never seize. */
    if (result) { fprintf(stderr, "Interface open failed 0x%08x\n", result); goto cleanup; }
    session->interface_open = 1;
    UInt8 number = 255, endpoints = 0;
    if ((*session->interface)->GetInterfaceNumber(session->interface, &number) || number != 0 ||
        (*session->interface)->GetNumEndpoints(session->interface, &endpoints) || endpoints != 2) goto cleanup;
    for (UInt8 pipe = 1; pipe <= endpoints; ++pipe) {
        UInt8 direction, endpoint, type, interval; UInt16 packet_size;
        if ((*session->interface)->GetPipeProperties(session->interface,pipe,&direction,&endpoint,&type,&packet_size,&interval)) goto cleanup;
        if (direction == kUSBIn && endpoint == 1 && type == kUSBInterrupt && packet_size == 64 && interval == 1) session->input = pipe;
        else if (direction == kUSBOut && endpoint == 1 && type == kUSBBulk && packet_size == 64 && interval == 1) session->output = pipe;
        else goto cleanup;
    }
    if (!session->input || !session->output) goto cleanup;
    result = (*session->interface)->CreateInterfaceAsyncEventSource(session->interface, &session->source);
    if (result || !session->source) goto cleanup;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), session->source, kCFRunLoopDefaultMode);
    status = 0;
cleanup:
    if (plugin) IODestroyPlugInInterface(plugin);
    if (interface_service) IOObjectRelease(interface_service);
    if (interfaces) IOObjectRelease(interfaces);
    if (target) IOObjectRelease(target);
    if (devices) IOObjectRelease(devices);
    if (status) fprintf(stderr, "Bootloader identity/interface guards failed; no OUT request sent.\n");
    return status;
}

static int open_session(ProgramSession *session) { return open_bootloader(session, expected_application); }

static void close_session(ProgramSession *session) {
    session->stopping = 1;
    if (session->interface_open) {
        if (session->write_pending) (*session->interface)->AbortPipe(session->interface, session->output);
        if (session->read_pending) (*session->interface)->AbortPipe(session->interface, session->input);
        uint64_t deadline = monotonic_nanoseconds() + UINT64_C(1000000000);
        while ((session->read_pending || session->write_pending) && monotonic_nanoseconds() < deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    }
    if (session->read_pending || session->write_pending) transport_quarantined = 1;
    if (session->source) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), session->source, kCFRunLoopDefaultMode);
        CFRelease(session->source);
    }
    if (session->interface_open) (*session->interface)->USBInterfaceClose(session->interface);
    if (session->interface) (*session->interface)->Release(session->interface);
    if (session->device_open) (*session->device)->USBDeviceClose(session->device);
    if (session->device) (*session->device)->Release(session->device);
}

/* Reads the complete flash through the bootloader's 40/47 read stream. */
static int capture_image(unsigned char output[IMAGE_SIZE], int application_version,
                         const unsigned char *expected_partial_image) {
    Reader *reader = calloc(1, sizeof(*reader));
    if (!reader) return 1;
    reader->expected_partial_image = expected_partial_image;
    ProgramSession session = {0};
    int status = 1;
    if (open_bootloader(&session, application_version)) goto cleanup;
    reader->interface = session.interface; reader->input_pipe = session.input;
    /* Arm the interrupt IN transfer BEFORE starting the read stream. */
    IOReturn result = (*session.interface)->ReadPipeAsync(session.interface, session.input, reader->packet,
        sizeof(reader->packet), received, reader);
    if (result) goto cleanup;
    reader->pending = 1;
    IOUSBDevRequestTO request = {0};
    request.noDataTimeout = 1000; request.completionTimeout = 1000;
    request.bmRequestType = 0x40;
    request.bRequest = 0x47;
    printf("read_stream_trigger=40 47 0000 0000 0000\n"); fflush(stdout);
    result = (*session.device)->DeviceRequestTO(session.device, &request);
    if (result) { fprintf(stderr, "Read trigger failed 0x%08x; no retry.\n", result); goto cleanup; }
    uint64_t deadline = monotonic_nanoseconds() + UINT64_C(10000000000);
    while (!interrupted && !reader->error && reader->count < BLOCKS && monotonic_nanoseconds() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    printf("read_frames=%u unique_blocks=%u duplicates=%u tag=%u zero_padded_frames=%u stale_partial_frames=%u\n",
           reader->packets, reader->count, reader->duplicates, reader->tag, reader->padded_frames, reader->stale_partial_frames);
    if (interrupted || !complete_image(reader)) {
        fprintf(stderr, "Incomplete or invalid backup; no image saved.\n"); goto cleanup;
    }
    memcpy(output, reader->image, IMAGE_SIZE);
    status = 0;
cleanup:
    reader->stopping = 1;
    if (reader->pending && session.interface_open) {
        /* AbortPipe cancels host reads; it sends no erase/reset command. */
        (*session.interface)->AbortPipe(session.interface, session.input);
        uint64_t drain_deadline = monotonic_nanoseconds() + UINT64_C(1000000000);
        while (reader->pending && monotonic_nanoseconds() < drain_deadline)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    }
    close_session(&session); /* The reader owns its read, so session.read_pending stays 0. */
    if (reader->pending) { transport_quarantined = 1; status = 1; }
    /* Keep callback storage alive if the host did not deliver abort completion.
     * This process exits immediately afterward, so no dangling callback target. */
    if (!reader->pending) free(reader);
    return status;
}

static int control_out(ProgramSession *session, unsigned code, unsigned address, unsigned timeout) {
    IOUSBDevRequestTO request = {0};
    request.bmRequestType = 0x40;
    request.bRequest = (UInt8)code;
    request.wValue = (UInt16)address;
    request.noDataTimeout = timeout;
    request.completionTimeout = timeout;
    IOReturn result = (*session->device)->DeviceRequestTO(session->device, &request);
    printf("program_control=40/%02x value=0x%04x timeout_ms=%u result=0x%08x\n", code, address, timeout, result);
    fflush(stdout);
    return result != kIOReturnSuccess;
}

static void pump_ms(unsigned milliseconds) {
    uint64_t deadline = monotonic_nanoseconds() + (uint64_t)milliseconds * 1000000;
    while (monotonic_nanoseconds() < deadline) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, true);
}

static int program_runs(ProgramSession *session, const Run runs[14], unsigned count) {
    IOReturn result = (*session->interface)->ReadPipeAsync(session->interface, session->input,
        session->packet, sizeof(session->packet), telemetry, session);
    if (result) return 1;
    session->read_pending = 1;
    for (unsigned i = 0; i < count; ++i) {
        const Run *run = runs + i;
        unsigned timeout = run->length / 64 * 35;
        /* Even a failed setup might have enabled programming; always disable. */
        int failed = interrupted || session->error;
        if (!failed) failed = control_out(session, 0x0d, run->address, 1000);
        /* Cancellation during the synchronous setup must disable reception
         * without submitting any new bulk payload. */
        if (interrupted || session->error) failed = 1;
        if (!failed) {
            session->written = 0; session->write_result = kIOReturnError;
            result = (*session->interface)->WritePipeAsyncTO(session->interface, session->output,
                (void *)(session->target + run->address), run->length, timeout, timeout, write_completed, session);
            if (result) failed = 1;
            else {
                session->write_pending = 1;
                uint64_t deadline = monotonic_nanoseconds() + (uint64_t)(timeout + 1000) * 1000000;
                while (session->write_pending && !session->error && !interrupted && monotonic_nanoseconds() < deadline)
                    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
                if (session->write_pending) {
                    (*session->interface)->AbortPipe(session->interface, session->output);
                    uint64_t drain = monotonic_nanoseconds() + UINT64_C(1000000000);
                    while (session->write_pending && monotonic_nanoseconds() < drain)
                        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
                    failed = 1;
                }
                if (session->write_result || session->written != run->length || session->error || interrupted) failed = 1;
            }
            printf("bulk_run=%u expected=%u actual=%zu result=0x%08x partial_frames=%u\n",
                   i, run->length, session->written, session->write_result, session->partial_frames);
        }
        if (!failed) pump_ms(100);
        if (control_out(session, 0x01, 0, 500)) failed = 1;
        if (session->error) failed = 1;
        if (failed) {
            fprintf(stderr, "Programming stopped; flash may be partially changed. Write-disable attempted. No retry or restart.\n");
            return 1;
        }
    }
    return 0;
}
