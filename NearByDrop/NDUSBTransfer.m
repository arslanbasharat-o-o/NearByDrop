#import "NDUSBTransfer.h"
#import "../Vendor/USB/include/libmtp.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

@implementation NDUSBTransfer { LIBMTP_mtpdevice_t *_device; }
- (instancetype)init { if ((self = [super init])) { static dispatch_once_t once; dispatch_once(&once, ^{ LIBMTP_Init(); }); } return self; }
- (void)close { if (_device) { LIBMTP_Release_Device(_device); _device = NULL; } }
- (void)dealloc { [self close]; }
- (void)fail:(NSError **)error message:(NSString *)message {
    if (error) *error = [NSError errorWithDomain:@"NearByDrop.USB" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
    if (_device) LIBMTP_Clear_Errorstack(_device);
}
static NSString *DeviceID(LIBMTP_raw_device_t d) { return [NSString stringWithFormat:@"%u:%u", d.bus_location, d.devnum]; }
- (NSArray *)devices:(NSError **)error {
    LIBMTP_raw_device_t *raw = NULL; int count = 0;
    LIBMTP_error_number_t result = LIBMTP_Detect_Raw_Devices(&raw, &count);
    if (result != LIBMTP_ERROR_NONE && result != LIBMTP_ERROR_NO_DEVICE_ATTACHED) { free(raw); [self fail:error message:@"Could not access USB devices. Reconnect your phone and try again."]; return nil; }
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        NSString *name = raw[i].device_entry.product ? [NSString stringWithUTF8String:raw[i].device_entry.product] : nil;
        [items addObject:@{@"id": DeviceID(raw[i]), @"name": name ?: @"Android phone"}];
    }
    free(raw); return items;
}
- (NSArray *)openDevice:(NSString *)identifier error:(NSError **)error {
    [self close];
    LIBMTP_raw_device_t *raw = NULL; int count = 0;
    LIBMTP_Detect_Raw_Devices(&raw, &count);
    for (int i = 0; i < count; i++) if ([DeviceID(raw[i]) isEqual:identifier]) { _device = LIBMTP_Open_Raw_Device_Uncached(&raw[i]); break; }
    free(raw);
    if (!_device) { [self fail:error message:@"Unlock your phone, choose File Transfer for USB, and close other Android transfer apps."]; return nil; }
    if (LIBMTP_Get_Storage(_device, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) { [self fail:error message:@"Phone storage is unavailable. Unlock your phone and reconnect it."]; [self close]; return nil; }
    NSMutableArray *items = [NSMutableArray array];
    for (LIBMTP_devicestorage_t *s = _device->storage; s; s = s->next) {
        NSString *name = s->StorageDescription ? [NSString stringWithUTF8String:s->StorageDescription] : nil;
        [items addObject:@{@"id": @(s->id), @"name": name ?: @"Phone storage"}];
    }
    return items;
}
- (NSArray *)filesInStorage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if (!_device) { [self fail:error message:@"Reconnect your phone to continue."]; return nil; }
    LIBMTP_Clear_Errorstack(_device);
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(_device, storage, parent);
    NSMutableArray *items = [NSMutableArray array];
    while (files) {
        LIBMTP_file_t *next = files->next;
        NSString *name = files->filename ? [NSString stringWithUTF8String:files->filename] : nil;
        if (name) [items addObject:@{@"id": @(files->item_id), @"name": name, @"size": @(files->filesize), @"folder": @(files->filetype == LIBMTP_FILETYPE_FOLDER)}];
        LIBMTP_destroy_file_t(files); files = next;
    }
    if (LIBMTP_Get_Errorstack(_device)) { [self fail:error message:@"Could not read this folder. Check the USB connection and unlock your phone."]; return nil; }
    return items;
}
static int Progress(uint64_t sent, uint64_t total, const void *context) {
    NDUSBTransfer *self = (__bridge NDUSBTransfer *)context;
    if (self.cancelRequested) return 1;
    if (self.progress) self.progress(total ? (double)sent / total : 0);
    return 0;
}
- (BOOL)upload:(NSURL *)url storage:(uint32_t)storage parent:(uint32_t)parent error:(NSError **)error {
    if (!_device || !url.isFileURL) { [self fail:error message:@"Choose a local file and connect your phone."]; return NO; }
    NSArray *siblings = [self filesInStorage:storage parent:parent error:error];
    if (!siblings) return NO;
    NSMutableSet *names = [NSMutableSet set];
    for (NSDictionary *item in siblings) [names addObject:item[@"name"]];
    NSString *original = url.lastPathComponent, *name = original;
    for (NSUInteger suffix = 2; [names containsObject:name]; suffix++) {
        NSString *stem = [original stringByDeletingPathExtension], *ext = original.pathExtension;
        name = [NSString stringWithFormat:@"%@ (%lu)%@%@", stem, (unsigned long)suffix, ext.length ? @"." : @"", ext];
    }
    int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || !S_ISREG(info.st_mode)) { if (fd >= 0) close(fd); [self fail:error message:@"This file cannot be read. Choose a regular file and try again."]; return NO; }
    LIBMTP_file_t *file = LIBMTP_new_file_t();
    if (!file) { close(fd); [self fail:error message:@"Could not prepare the transfer."]; return NO; }
    file->filename = strdup(name.UTF8String);
    file->filesize = info.st_size;
    file->parent_id = parent == LIBMTP_FILES_AND_FOLDERS_ROOT ? 0 : parent;
    file->storage_id = storage;
    file->filetype = LIBMTP_FILETYPE_UNKNOWN;
    int result = LIBMTP_Send_File_From_File_Descriptor(_device, fd, file, Progress, (__bridge const void *)self);
    close(fd);
    LIBMTP_destroy_file_t(file);
    if (result) { [self fail:error message:self.cancelRequested ? @"Transfer canceled. A partial file may remain on the phone." : @"USB transfer failed. Check the connection and available space on your phone."]; return NO; }
    return YES;
}
- (NSURL *)download:(uint32_t)item name:(NSString *)name directory:(NSURL *)directory error:(NSError **)error {
    if (!_device || !directory.isFileURL) { [self fail:error message:@"Reconnect your phone to continue."]; return nil; }
    NSString *safe = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"_"] lastPathComponent];
    safe = [safe stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    if (!safe.length || [safe isEqual:@"."] || [safe isEqual:@".."]) safe = @"Received file";
    NSURL *destination = nil; int fd = -1;
    for (NSUInteger suffix = 1; suffix < 10000; suffix++) {
        NSString *candidate = safe;
        if (suffix > 1) candidate = [NSString stringWithFormat:@"%@ (%lu)%@%@", safe.stringByDeletingPathExtension, (unsigned long)suffix, safe.pathExtension.length ? @"." : @"", safe.pathExtension];
        destination = [directory URLByAppendingPathComponent:candidate isDirectory:NO];
        fd = open(destination.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0600);
        if (fd >= 0 || errno != EEXIST) break;
    }
    if (fd < 0) { [self fail:error message:@"Could not create a file in Downloads."]; return nil; }
    int result = LIBMTP_Get_File_To_File_Descriptor(_device, item, fd, Progress, (__bridge const void *)self);
    if (fsync(fd) && result == 0) result = -1;
    close(fd);
    if (result) { unlink(destination.fileSystemRepresentation); [self fail:error message:self.cancelRequested ? @"Transfer canceled." : @"USB transfer failed. Reconnect your phone and try again."]; return nil; }
    return destination;
}
@end
