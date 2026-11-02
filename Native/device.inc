static unsigned device_location;

static io_service_t discover(void) {
    if (transport_quarantined || interrupted) return IO_OBJECT_NULL;
    io_iterator_t iterator=IO_OBJECT_NULL;io_service_t service,target=IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching(kIOUSBDeviceClassName),&iterator)) return IO_OBJECT_NULL;
    unsigned count=0;
    while ((service=IOIteratorNext(iterator))) {
        if (property(service,CFSTR("idVendor"))==0x044f) {
            ++count;
            if (!target) {IOObjectRetain(service);target=service;}
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (count!=1) {
        if (target) IOObjectRelease(target);
        state_name=count?"multiple_devices":"disconnected";return IO_OBJECT_NULL;
    }
    uint64_t registry=0;
    if (IORegistryEntryGetRegistryEntryID(target,&registry) || !registry ||
        (bound_registry && registry!=bound_registry)) {state_name="unsupported";IOObjectRelease(target);return IO_OBJECT_NULL;}
    bound_registry=registry;status_pid=property(target,CFSTR("idProduct"));
    device_location=property(target,CFSTR("locationID"));
    return target;
}

static IOUSBDeviceInterface **open_device(io_service_t service) {
    IOCFPlugInInterface **plugin=NULL;IOUSBDeviceInterface **device=NULL;SInt32 score=0;
    IOReturn result=IOCreatePlugInInterfaceForService(service,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
    if (result || !plugin) return NULL;
    HRESULT queried=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320),(LPVOID *)&device);
    IODestroyPlugInInterface(plugin);
    if (queried || !device) return NULL;
    if ((*device)->USBDeviceOpen(device)) {(*device)->Release(device);return NULL;}
    return device;
}

static void close_device(IOUSBDeviceInterface **device) {
    if (device) {(*device)->USBDeviceClose(device);(*device)->Release(device);}
}

static int model_matches(IOUSBDeviceInterface **device) {
    unsigned char data[16]={0};IOUSBDevRequestTO request={0};
    request.bmRequestType=0xc1;request.bRequest=0x49;request.wLength=16;request.pData=data;
    request.noDataTimeout=1000;request.completionTimeout=1000;
    return !(*device)->DeviceRequestTO(device,&request) && request.wLenDone==16 &&
        data[0]==0x49 && !data[1] && data[6]==6 && data[7]==3;
}

static int normal_version(IOUSBDeviceInterface **device) {
    unsigned char data[8]={0};IOUSBDevRequestTO request={0};
    request.bmRequestType=0xc1;request.bRequest=0x56;request.wLength=8;request.pData=data;
    request.noDataTimeout=1000;request.completionTimeout=1000;
    if ((*device)->DeviceRequestTO(device,&request) || request.wLenDone<3 || request.wLenDone>8 || data[0]!=0x56) return 1;
    observed_application=data[1]|((unsigned)data[2]<<8);return 0;
}

static int probe_status(void) {
    io_service_t service=discover();if (!service) return !strcmp(state_name,"disconnected")?0:1;
    IOUSBDeviceInterface **device=open_device(service);IOObjectRelease(service);
    if (!device) return 1;
    int bad=1;
    if (status_pid==0xb676) {bad=!versions_match(device,-1) || !descriptor_matches(device);if (!bad) state_name="recovery";}
    else if (status_pid==0xb677) {bad=normal_version(device);if (!bad) state_name="normal";}
    else if (status_pid==0xb65d) {bad=!model_matches(device);observed_application=-1;if (!bad) state_name="normal";}
    close_device(device);return bad;
}

static int bind_bootloader(int application, unsigned location) {
    if (probe_status() || status_pid!=0xb676 || strcmp(state_name,"recovery") ||
        (application>=0 && observed_application!=application) || (location && device_location!=location)) return 1;
    return 0;
}

/* Called only after a fresh full target verification and durable restart marker. */
static int restart_and_confirm(unsigned location, unsigned version) {
    io_service_t service=discover();if (!service) return 1;
    IOUSBDeviceInterface **device=open_device(service);IOObjectRelease(service);
    if (!device) return 1;
    if (status_pid!=0xb676 || device_location!=location || !versions_match(device,(int)version) || !descriptor_matches(device) || interrupted) {close_device(device);return 1;}
    IOUSBDevRequestTO request={0};request.bmRequestType=0x40;request.bRequest=0x24;
    request.noDataTimeout=1000;request.completionTimeout=1000;
    restart_issued=1;
    IOReturn result=(*device)->DeviceRequestTO(device,&request);
    printf("restart_once_result=0x%08x; checking re-enumeration, no reset retry\n",result);
    close_device(device);
    uint64_t old_registry=bound_registry;
    int initialized=0;
    uint64_t deadline=monotonic_nanoseconds()+UINT64_C(20000000000);
    while (!interrupted && monotonic_nanoseconds()<deadline) {
        bound_registry=0;service=discover();
        if (!service) {pump_ms(200);continue;}
        if (device_location!=location || (status_pid!=0xb65d && status_pid!=0xb677) || bound_registry==old_registry) {
            IOObjectRelease(service);pump_ms(200);continue;
        }
        device=open_device(service);IOObjectRelease(service);
        if (!device) {pump_ms(200);continue;}
        if (status_pid==0xb677) {
            /* A read that fails right after re-enumeration is retried until the
             * deadline; only a successful read of the wrong version is final. */
            int unread=normal_version(device);
            int good=!unread && observed_application==(int)version;
            close_device(device);
            if (good) {state_name="normal";return 0;}
            if (unread) {pump_ms(200);continue;}
            return 1;
        }
        if (initialized) {close_device(device);pump_ms(200);continue;}
        if (!model_matches(device)) {close_device(device);pump_ms(200);continue;}
        request=(IOUSBDevRequestTO){0};request.bmRequestType=0x41;request.bRequest=0x53;request.wValue=6;
        request.noDataTimeout=1000;request.completionTimeout=1000;
        initialized=1;result=(*device)->DeviceRequestTO(device,&request);
        printf("normal_initialization_once_result=0x%08x\n",result);close_device(device);pump_ms(300);
    }
    return 1;
}
