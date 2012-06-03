
#import <SystemConfiguration/SystemConfiguration.h>
#import "MCCloudResetSentinel.h"
#import "NSURLExtensions.h"

NSString * const MCCloudResetSentinelDidDetectResetNotification = @"MCCloudResetSentinelDidDetectResetNotification"; 
NSString * const MCSentinelException = @"MCSentinelException";

static NSString * const MCSyncingDevicesListFilename = @"MCSyncingDevices.plist";

@interface MCCloudResetSentinel ()

@property (nonatomic, readwrite, assign) BOOL cloudSyncEnabled;
@property (nonatomic, readonly, strong) NSURL *syncedDevicesListURL;

@end

@implementation MCCloudResetSentinel {
    NSMetadataQuery *devicesListMetadataQuery;
}

@synthesize cloudSyncEnabled;
@synthesize cloudStoreURL;
@synthesize delegate;

-(id)initWithCloudStorageURL:(NSURL *)newURL cloudSyncEnabled:(BOOL)usingStorage
{
    self = [super init];
    if ( self ) {
        cloudStoreURL = [newURL copy];
        cloudSyncEnabled = usingStorage;
        if ( !cloudStoreURL ) [NSException raise:MCSentinelException format:@"Attempt to init a sentinel with cloudStoreURL nil"];
        
        // Listen for changes in the metadata of the devices list
        devicesListMetadataQuery = [[NSMetadataQuery alloc] init];
        devicesListMetadataQuery.searchScopes = [NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope];
        devicesListMetadataQuery.predicate = [NSPredicate predicateWithFormat:@"%K like %@", NSMetadataItemFSNameKey, MCSyncingDevicesListFilename];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(devicesListDidUpdate:) name:NSMetadataQueryDidUpdateNotification object:devicesListMetadataQuery];
        [devicesListMetadataQuery startQuery];
    }
    return self;
}

-(void)dealloc
{   
    [self stopMonitoringDevicesList];
}

#pragma mark Monitoring

-(void)stopMonitoringDevicesList
{
    [devicesListMetadataQuery disableUpdates];
    [devicesListMetadataQuery stopQuery];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    devicesListMetadataQuery = nil;
}

#pragma mark Metadata Change Notifications

-(void)devicesListDidUpdate:(NSNotification *)notif
{
    [self checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
        if ( !deviceIsPresent && cloudSyncEnabled ) {
            [delegate cloudResetSentinelDidDetectReset:self];
            [[NSNotificationCenter defaultCenter] postNotificationName:MCCloudResetSentinelDidDetectResetNotification object:self userInfo:nil];
        }
    }];
}

#pragma mark Managing Devices List

+(NSString *)devicesListFilename
{
    return MCSyncingDevicesListFilename;
}

-(void)checkCurrentDeviceRegistration:(void (^)(BOOL deviceIsRegistered))completionBlock
{
    if ( completionBlock ) completionBlock = [completionBlock copy];
    
    dispatch_queue_t completionQueue = dispatch_get_current_queue();
    dispatch_retain(completionQueue);
        
    NSURL *url = self.syncedDevicesListURL;
    [url syncWithCloud:^(BOOL succeeded, NSError *error) {        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *readURL) {
            NSArray *devices = [NSArray arrayWithContentsOfURL:readURL];
            NSString *deviceId = [self.class deviceIdentifier];
            BOOL deviceIsRegistered = [devices containsObject:deviceId];
            dispatch_async(completionQueue, ^{
                if ( completionBlock ) completionBlock(deviceIsRegistered);
                dispatch_release(completionQueue);
            });
        }];
    }];
}

-(NSURL *)syncedDevicesListURL
{
    NSURL *storeURL = self.cloudStoreURL;
    return [storeURL URLByAppendingPathComponent:MCSyncingDevicesListFilename];
}

+(NSString *)deviceIdentifier
{
    static NSString * const MCAppUniqueId = @"MCAppUniqueId";
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *uniqueId = [defs stringForKey:MCAppUniqueId];
    if ( !uniqueId ) {
        uniqueId = [[NSProcessInfo processInfo] globallyUniqueString];
        [defs setObject:uniqueId forKey:MCAppUniqueId];
        [defs synchronize];
    }
    return uniqueId;
}

-(void)updateDevicesList:(void (^)(void))completionBlock
{
    NSURL *url = self.syncedDevicesListURL;
    if ( !url ) [NSException raise:MCSentinelException format:@"Attempt to update devices list with iCloud syncing disabled."];
    
    if ( completionBlock ) completionBlock = [completionBlock copy];
    
    dispatch_queue_t completionQueue = dispatch_get_current_queue();
    dispatch_retain(completionQueue);
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [url syncWithCloud:^(BOOL succeeded, NSError *error) {
            if ( !succeeded ) return;
            
            __block BOOL updated = NO;
            __block NSMutableArray *devices = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
            [coordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *readURL) {
                devices = [NSMutableArray arrayWithContentsOfURL:readURL];
                if ( !devices ) devices = [NSMutableArray array]; 
                NSString *deviceId = [self.class deviceIdentifier];
                
                if ( ![devices containsObject:deviceId] && cloudSyncEnabled ) {
                    [devices addObject:deviceId];
                    updated = YES;
                } 
            }];
            
            [coordinator coordinateWritingItemAtURL:self.cloudStoreURL options:0 error:NULL byAccessor:^(NSURL *newURL) {
                [[NSFileManager defaultManager] createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:NULL];
            }];
            
            if ( updated ) [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:NULL byAccessor:^(NSURL *writeURL) {
                [devices writeToURL:writeURL atomically:YES];
            }];
            
            dispatch_async(completionQueue, ^{
                if ( completionBlock ) completionBlock();
                dispatch_release(completionQueue);
            });
        }];
    });
}

@end
