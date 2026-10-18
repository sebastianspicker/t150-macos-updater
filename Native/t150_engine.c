/* Native T150 updater engine. No vendor firmware is embedded or distributed.
 * Each invocation is a one-shot process protected by a per-user engine lock.
 */
#include "transport.inc"
#include "storage.inc"
#include "policy.inc"
#include "device.inc"
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>

static IOPMAssertionID sleep_assertion=kIOPMNullAssertionID, idle_assertion=kIOPMNullAssertionID;
static void release_sleep_assertions(void) {
    if (sleep_assertion!=kIOPMNullAssertionID) IOPMAssertionRelease(sleep_assertion);
    if (idle_assertion!=kIOPMNullAssertionID) IOPMAssertionRelease(idle_assertion);
}
static int prevent_sleep(void) {
    if (IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,kIOPMAssertionLevelOn,
        CFSTR("T150 firmware operation"),&idle_assertion)!=kIOReturnSuccess) return 1;
    if (IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep,kIOPMAssertionLevelOn,
        CFSTR("T150 firmware operation"),&sleep_assertion)!=kIOReturnSuccess) {release_sleep_assertions();return 1;}
    return atexit(release_sleep_assertions)!=0;
}
static int on_ac_power(void) {
    CFTypeRef info=IOPSCopyPowerSourcesInfo();
    if (!info) return 0;
    CFStringRef source=IOPSGetProvidingPowerSourceType(info);
    int available=source && CFEqual(source,CFSTR(kIOPMACPowerKey));
    CFRelease(info);return available;
}

/* Tests replace this internal table at compile time in their own executable.
 * No CLI option, manifest field, or environment variable changes USB behavior. */
typedef struct {
    int (*bind)(int,unsigned);
    int (*capture)(unsigned char *,int,const unsigned char *);
    int (*open)(ProgramSession *);
    int (*program)(ProgramSession *,const Run *,unsigned);
    void (*close)(ProgramSession *);
    int (*restart)(unsigned,unsigned);
    int (*ac_power)(void);
} EngineIO;
static EngineIO engine_io={bind_bootloader,capture_image,open_session,program_runs,close_session,restart_and_confirm,on_ac_power};

static int prepare_operation(const char *firmware, const char *profile_name) {
    unsigned char *decoded=malloc(CONTAINER_SIZE),*a=malloc(IMAGE_SIZE),*b=malloc(IMAGE_SIZE),*target=malloc(IMAGE_SIZE);
    if (!decoded || !a || !b || !target) return emit_result(0,"memory","Cannot allocate verification buffers.");
    const TargetProfile *profile=find_profile(profile_name);
    if (!profile || !patches_valid(profile) || external_read(firmware,decoded,CONTAINER_SIZE) || !hash_matches(decoded,CONTAINER_SIZE,decoded_sha))
        return emit_result(0,"unreviewed_firmware","Only the compiled, reviewed T150 V35 decoded firmware and a compiled target profile are accepted.");
    select_profile(profile);
    const char *reserved[]={"firmware.tmf","backup-a.bin","backup-b.bin","target.bin","manifest.bin","manifest.json","apply-started","applied","restart-started","finished"};
    for (unsigned i=0;i<sizeof(reserved)/sizeof(*reserved);++i)
        if (artifact_exists(reserved[i])) return emit_result(0,"session_used","Use a new private session directory; an existing artifact will not be overwritten.");
    if (capture_log("prepare.log")) return emit_result(0,"log","Cannot reserve the prepare log.");
    if (engine_io.bind(-1,0)) return emit_result(0,"recovery_required","Enter the official T150 recovery mode; exactly one supported bootloader is required.");
    int current=observed_application;
    unsigned version=profile->version;
    if (current<=0 || (unsigned)current>version)
        return emit_result(0,"downgrade_refused","Installed version must be older than the reviewed target. Downgrades and unreviewed same-version writes are prohibited.");
    if ((unsigned)current==version && !baseline_count(profile))
        return emit_result(0,"same_version_refused","The wheel already reports the target version and this target accepts no same-version starting image. No backups were read; no firmware written.");
    if (save_at("firmware.tmf",decoded,CONTAINER_SIZE) ||
        engine_io.capture(a,current,NULL) || save_at("backup-a.bin",a,IMAGE_SIZE) ||
        engine_io.capture(b,current,NULL) || save_at("backup-b.bin",b,IMAGE_SIZE))
        return emit_result(0,"backup_failed","Both complete backups must be captured and durably saved. No firmware was written.");
    if (memcmp(a,b,IMAGE_SIZE)) return emit_result(0,"backups_differ","Independent full flash backups differ. No firmware was written.");
    /* Only reached at the same version: the flash already holds this exact target. */
    if (hash_matches(a,IMAGE_SIZE,profile->target_sha))
        return emit_result(0,"already_current","The wheel already contains exactly this reviewed firmware image. Backups retained; no firmware written.");
    if (construct_target(profile,a,(unsigned)current,decoded,target,result_runs,&result_run_count))
        return emit_result(0,"unsupported_baseline",(unsigned)current==version
            ?"The wheel reports the target version but its flash is none of the reviewed V35 images (official, fixes, full, sibling mimic), or the bootloader, vectors, footer or reviewed target validation failed. Backups retained; no firmware written."
            :"Bootloader hash, application vectors/footer, installed image, or reviewed target validation failed. Backups retained; no firmware written.");
    Manifest manifest=make_manifest(profile,a,(unsigned)current,bound_registry,device_location);
    if (save_at("target.bin",target,IMAGE_SIZE) || save_manifest(&manifest))
        return emit_result(0,"persistence","Cannot durably save the verified session manifest.");
    free(decoded);free(a);free(b);free(target);
    return emit_result(1,"prepared","Two matching full backups and a reviewed application-only plan are ready. No firmware was written.");
}

static int apply_operation(void) {
    if (artifact_exists("apply-started") || artifact_exists("restart-started"))
        return emit_result(0,"attempt_recorded","This session already started an update. Do not retry or restart after an uncertain result.");
    unsigned char *baseline=malloc(IMAGE_SIZE),*target=malloc(IMAGE_SIZE),*fresh=malloc(IMAGE_SIZE);
    Manifest manifest;
    if (!baseline || !target || !fresh) return emit_result(0,"memory","Cannot allocate verification buffers.");
    if (load_session(&manifest,baseline,target)) return emit_result(0,"session_invalid","Session artifacts, backup agreement, bootloader identity, or compiled profile validation failed.");
    if (!engine_io.ac_power()) return emit_result(0,"ac_power_required","Connect the Mac to external power before programming firmware.");
    if (capture_log("apply.log")) return emit_result(0,"log","Cannot reserve the apply log.");
    bound_registry=manifest.registry;expected_application=(int)manifest.application;
    if (engine_io.bind(expected_application,manifest.location)) return emit_result(0,"device_changed","The prepared bootloader device or installed version changed. No firmware written.");
    if (engine_io.capture(fresh,expected_application,NULL) || save_at("before-apply.bin",fresh,IMAGE_SIZE) || memcmp(fresh,baseline,IMAGE_SIZE))
        return emit_result(0,"baseline_changed","Fresh complete flash did not match both prepared backups. No firmware written.");
    ProgramSession *transport=calloc(1,sizeof(*transport));
    if (!transport) return emit_result(0,"memory","Cannot allocate USB state.");
    transport->target=target;
    if (engine_io.open(transport)) {
        engine_io.close(transport);
        return emit_result(0,"device_changed","The bootloader programming session could not be opened. No programming command was sent; no firmware written.");
    }
    /* Persist the no-retry marker before any programming command is possible. */
    if (save_at("apply-started",active_profile->target_sha,65)) {
        engine_io.close(transport);
        return emit_result(0,"marker_failed","Cannot durably record the write marker. No programming command was sent; no firmware written.");
    }
    int failed=engine_io.program(transport,result_runs,result_run_count);
    engine_io.close(transport);
    if (failed || transport_quarantined || interrupted)
        return emit_result(0,"programming_stopped","Programming stopped; flash may be partially changed. Write-disable was attempted after any programming setup. Do not retry or restart; retain this session for reviewed recovery.");
    if (engine_io.capture(fresh,(int)active_profile->version,target) || save_at("readback.bin",fresh,IMAGE_SIZE) || memcmp(fresh,target,IMAGE_SIZE))
        return emit_result(0,"verification_failed","Full post-write verification failed. No restart; retain backups and readback for reviewed recovery.");
    if (save_at("applied",active_profile->target_sha,65)) return emit_result(0,"persistence","Target verified but completion could not be durably recorded. No restart.");
    free(transport);free(baseline);free(target);free(fresh);
    return emit_result(1,"applied","All 65536 bytes verified, including unchanged bootloader. Restart remains a separate confirmed step.");
}

static int finish_operation(void) {
    if (artifact_exists("restart-started")) return emit_result(0,"restart_recorded","A restart was already attempted. Check status; do not automatically repeat restart.");
    unsigned char *baseline=malloc(IMAGE_SIZE),*target=malloc(IMAGE_SIZE),*fresh=malloc(IMAGE_SIZE);
    char marker[65];Manifest manifest;
    if (!baseline || !target || !fresh) return emit_result(0,"memory","Cannot allocate verification buffers.");
    if (load_session(&manifest,baseline,target) || safe_read_at(session_fd,"applied",marker,sizeof(marker)) ||
        memcmp(marker,active_profile->target_sha,65) || safe_read_at(session_fd,"readback.bin",fresh,IMAGE_SIZE) || memcmp(fresh,target,IMAGE_SIZE))
        return emit_result(0,"session_invalid","A valid session and complete verified post-write image are required before restart.");
    if (capture_log("finish.log")) return emit_result(0,"log","Cannot reserve the finish log.");
    bound_registry=manifest.registry;
    int version=(int)active_profile->version;
    if (engine_io.bind(version,manifest.location) || engine_io.capture(fresh,version,target) ||
        save_at("before-restart.bin",fresh,IMAGE_SIZE) || memcmp(fresh,target,IMAGE_SIZE))
        return emit_result(0,"verification_failed","Fresh complete target verification or device identity failed. No restart.");
    if (interrupted || save_at("restart-started",active_profile->target_sha,65)) return emit_result(0,"persistence","Cannot durably record restart intent. No restart.");
    if (engine_io.restart(manifest.location,(unsigned)version))
        return emit_result(0,"normal_verification_failed","Restart or normal-mode verification did not complete. Do not repeat reset; check connection and status.");
    if (save_at("finished",active_profile->target_sha,65)) return emit_result(0,"persistence","Normal-mode target version confirmed but completion record could not be saved.");
    free(baseline);free(target);free(fresh);
    return emit_result(1,"finished","The verified target image was restarted and the wheel reports the target version in normal mode.");
}

static int offline_tests(void) {
    unsigned char *before=calloc(1,IMAGE_SIZE),*target=calloc(1,IMAGE_SIZE);
    Reader *reader=calloc(1,sizeof(*reader));Run runs[14]={{0}};
    if (!before || !target || !reader) return 1;
    if (make_runs(before,target,runs)) return 1;
    target[0]=1;if (make_runs(before,target,runs)) return 1; /* Boot never enters plan. */
    target[0x2000]=1;target[0x3000]=1;target[0x5000]=1;target[0xffff]=1;
    if (make_runs(before,target,runs)!=3 || runs[0].address!=0x2000 || runs[0].length!=8192 || runs[1].address!=0x5000 || runs[2].address!=0xf000) return 1;
    memset(target+0x2000,1,IMAGE_SIZE-0x2000);
    if (make_runs(before,target,runs)!=1 || runs[0].address!=0x2000 || runs[0].length!=57344) return 1;
    const TargetProfile *official=find_profile("t150-v35-boot5");
    if (!official || baseline_valid(official,before,5) || baseline_valid(official,before,35) || baseline_valid(official,before,36)) return 1;
    for (unsigned i=0;i<PROFILE_SLOTS;++i) {
        const TargetProfile *profile=profiles+i;
        if (!profile->name) continue;
        if (find_profile(profile->name)!=profile || strlen(profile->name)>=sizeof(((Manifest *)0)->profile) ||
            !patches_valid(profile) || strlen(profile->target_sha)!=64 ||
            (profile->patch_count && profile->version!=official->version)) return 1;
        /* The same-version baselines are exactly the other compiled profiles of the
         * same version: every reviewed image reaches, and reverts to, every other one. */
        unsigned siblings=0;
        for (unsigned k=0;k<PROFILE_SLOTS;++k) {
            if (!profiles[k].name || profiles+k==profile || profiles[k].version!=profile->version) continue;
            ++siblings;int listed=0;
            for (unsigned j=0;j<baseline_count(profile);++j) if (!strcmp(profile->same_version_baselines[j],profiles[k].target_sha)) listed=1;
            if (!listed) return 1;
        }
        if (siblings!=baseline_count(profile)) return 1;
    }
    unsigned char packet[36]={3};
    for (unsigned i=BLOCKS;i--;) {
        unsigned address=i*32;packet[1]=(unsigned char)address;packet[2]=(unsigned char)(address>>8);memset(packet+3,(unsigned char)i,32);
        if (accept_packet(reader,packet,sizeof(packet))) return 1;
    }
    if (!complete_image(reader)) return 1;
    if (accept_packet(reader,packet,sizeof(packet)) || reader->duplicates!=1) return 1;
    packet[3]^=1;if (!accept_packet(reader,packet,sizeof(packet))) return 1;packet[3]^=1;
    packet[35]=1;if (!accept_packet(reader,packet,sizeof(packet))) return 1;packet[35]=0;
    packet[0]=5;if (!accept_packet(reader,packet,sizeof(packet))) return 1;packet[0]=3;
    if (!accept_packet(reader,packet,34) || !accept_packet(reader,packet,37)) return 1;
    packet[1]=1;if (!accept_packet(reader,packet,sizeof(packet))) return 1;
    Reader partial={0};partial.expected_partial_image=target;packet[0]=4;packet[1]=0;packet[2]=0x21;memcpy(packet+3,target+0x2000,32);
    if (accept_packet(&partial,packet,sizeof(packet)) || partial.count || partial.stale_partial_frames!=1) return 1;
    packet[3]^=1;if (!accept_packet(&partial,packet,sizeof(packet))) return 1;
    packet[3]^=1;packet[2]=0;memcpy(packet+3,target+0xff00,32);if (!valid_partial(packet,sizeof(packet),target)) return 1;
    free(before);free(target);free(reader);
    puts("PASS: compiled target table, dynamic application-page planning, boot exclusion, invalid baseline/version refusal, complete out-of-order coverage, duplicate conflicts, frame bounds/padding, stale telemetry never establishes coverage");return 0;
}

static const char *option_value(int argc,char **argv,const char *name) {
    for (int i=2;i+1<argc;++i) if (!strcmp(argv[i],name)) return argv[i+1];
    return NULL;
}

int main(int argc,char **argv) {
    umask(0077);
    if (argc==2 && !strcmp(argv[1],"self-test")) return offline_tests();
    if (argc<2) {fprintf(stderr,"Expected status, prepare, apply, finish, or self-test.\n");return 2;}
    operation=argv[1];
    const char *result=option_value(argc,argv,"--result");
    if (!result || (result_fd=fresh_result(result))<0) {fprintf(stderr,"A fresh --result file in an owned0700 directory is required.\n");return 2;}
    if (strcmp(operation,"status") && strcmp(operation,"prepare") && strcmp(operation,"apply") && strcmp(operation,"finish")) return emit_result(0,"arguments","Unsupported operation.");
    int confirmation=0,seen_result=0,seen_session=0,seen_firmware=0,seen_profile=0;
    for (int i=2;i<argc;++i) {
        int *seen=NULL;
        if (!strcmp(argv[i],"--result")) seen=&seen_result;
        else if (strcmp(operation,"status") && !strcmp(argv[i],"--session")) seen=&seen_session;
        else if (!strcmp(operation,"prepare") && !strcmp(argv[i],"--firmware")) seen=&seen_firmware;
        else if (!strcmp(operation,"prepare") && !strcmp(argv[i],"--profile")) seen=&seen_profile;
        if (seen) {
            if ((*seen)++ || ++i>=argc || !strncmp(argv[i],"--",2)) return emit_result(0,"arguments","Missing or repeated option value.");
        }
        else if ((!strcmp(operation,"apply") && !strcmp(argv[i],"--confirm-program")) || (!strcmp(operation,"finish") && !strcmp(argv[i],"--confirm-restart"))) {
            if (confirmation++) return emit_result(0,"arguments","Repeated confirmation option.");
        }
        else return emit_result(0,"arguments","Unexpected option.");
    }
    if ((!strcmp(operation,"apply") || !strcmp(operation,"finish")) && !confirmation) return emit_result(0,"confirmation_required","Explicit operator confirmation flag is required.");
    if (global_lock()) return emit_result(0,"busy","Another native engine operation is active, or the private lock is unavailable.");
    signal(SIGINT,interrupt_operation);signal(SIGTERM,interrupt_operation);
    if (!strcmp(operation,"status")) {
        int bad=probe_status();
        return emit_result(!bad,bad?"status_unavailable":"status",bad?"USB status query failed or device is unsupported.":"Read-only USB status complete.");
    }
    if (prevent_sleep()) return emit_result(0,"sleep_assertion","Cannot hold macOS sleep prevention for the operation.");
    const char *session=option_value(argc,argv,"--session");
    if (!session || (session_fd=directory_path(session))<0 || !private_directory(session_fd)) return emit_result(0,"session_directory","Session must be an existing owned0700 directory with no symlink path components.");
    session_path=session;
    if (!strcmp(operation,"prepare")) {
        const char *firmware=option_value(argc,argv,"--firmware"),*profile=option_value(argc,argv,"--profile");
        if (!firmware || !profile) return emit_result(0,"arguments","prepare requires --firmware with the reviewed decoded file and --profile with a compiled target name.");
        return prepare_operation(firmware,profile);
    }
    if (!strcmp(operation,"apply")) return apply_operation();
    return finish_operation();
}
