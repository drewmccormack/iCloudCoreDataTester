
#import <SystemConfiguration/SystemConfiguration.h>
#import "MCCloudResetSentinel.h"
#import "NSURLExtensions.h"

NSString * const MCCloudResetSentinelDidDetectResetNotification = @"MCCloudResetSentinelDidDetectResetNotification"; 
NSString * const MCSentinelException = @"MCSentinelException";

NSString * const MCCloudResetSentinelSyncDataSetIDUserDefaultKey = @"MCCloudResetSentinelSyncDataSetIDUserDefaultKey";

static NSString * const MCSyncingDevicesListFilename = @"MCSyncingDevices.plist";
static NSString * const MCSentinelAppUniqueIdDefault = @"MCSentinelAppUniqueIdDefault";

@interface MCCloudResetSentinel ()

@property (nonatomic, readonly, strong) NSURL *syncedDevicesListURL;

@end

@implementation MCCloudResetSentinel {
    NSMetadataQuery *devicesListMetadataQuery;
    BOOL haveInformedDelegateOfReset;
    BOOL performingDeviceRegistrationCheck;
    NSOperationQueue *filePresenterQueue;
}

@synthesize cloudStoreURL;
@synthesize delegate;

-(id)initWithCloudStorageURL:(NSURL *)newURL
{
    self = [super init];
    if ( self ) {
        haveInformedDelegateOfReset = NO;
        performingDeviceRegistrationCheck = NO;
        filePresenterQueue = [[NSOperationQueue alloc] init];
        
        cloudStoreURL = [newURL copy];
        if ( !cloudStoreURL ) [NSException raise:MCSentinelException format:@"Attempt to init a sentinel with cloudStoreURL nil"];
        
        // Listen for changes in the metadata of the devices list
        devicesListMetadataQuery = [[NSMetadataQuery alloc] init];
        devicesListMetadataQuery.searchScopes = [NSArray arrayWithObject:NSMetadataQueryUbiquitousDataScope];
        devicesListMetadataQuery.predicate = [NSPredicate predicateWithFormat:@"%K like %@", NSMetadataItemFSNameKey, MCSyncingDevicesListFilename];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(devicesListDidUpdate:) name:NSMetadataQueryDidUpdateNotification object:devicesListMetadataQuery];
        if ( ![devicesListMetadataQuery startQuery] ) NSLog(@"Failed to start devices list NSMetadataQuery");
        
        // Register as file presenter
        [NSFileCoordinator addFilePresenter:self];
    }
    return self;
}

-(void)dealloc
{   
    [self stopMonitoringDevicesList];
}

#pragma mark File Presenter Protocol

-(NSURL *)presentedItemURL
{
    return self.syncedDevicesListURL;
}

-(NSOperationQueue *)presentedItemOperationQueue
{
    return filePresenterQueue;
}

-(void)presentedItemDidChange
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self devicesListDidUpdate:nil];
    }];
}

-(void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self devicesListDidUpdate:nil];
    }];
    completionHandler(nil);
}

#pragma mark Monitoring

-(void)stopMonitoringDevicesList
{
    [NSFileCoordinator removeFilePresenter:self];
    [devicesListMetadataQuery disableUpdates];
    [devicesListMetadataQuery stopQuery];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    devicesListMetadataQuery = nil;
}

#pragma mark Metadata Change Notifications

-(void)devicesListDidUpdate:(NSNotification *)notif
{
    if ( haveInformedDelegateOfReset || performingDeviceRegistrationCheck ) return;
    [devicesListMetadataQuery disableUpdates];
    performingDeviceRegistrationCheck = YES;
    [self checkCurrentDeviceRegistration:^(BOOL deviceIsPresent) {
        performingDeviceRegistrationCheck = NO;
        if ( !deviceIsPresent ) {
            haveInformedDelegateOfReset = YES;
            [self stopMonitoringDevicesList];
            [delegate cloudResetSentinelDidDetectReset:self];
            [[NSNotificationCenter defaultCenter] postNotificationName:MCCloudResetSentinelDidDetectResetNotification object:self userInfo:nil];
        }
        else {
            [devicesListMetadataQuery enableUpdates];
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
        if ( !succeeded ) NSLog(@"%@", error);
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
        error = nil;
        [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *readURL) {
            NSDictionary *plist = [NSDictionary dictionaryWithContentsOfURL:readURL];
            NSArray *devices = [plist objectForKey:@"devices"];
            NSString *deviceId = [self.class deviceIdentifier];
            BOOL deviceIsRegistered = [devices containsObject:deviceId];
            
            NSString *dataset = [plist objectForKey:@"dataset"];
            NSString *defaultsDataset = [[NSUserDefaults standardUserDefaults] stringForKey:MCCloudResetSentinelSyncDataSetIDUserDefaultKey];
            deviceIsRegistered &= [dataset isEqualToString:defaultsDataset];
            
            dispatch_async(completionQueue, ^{
                if ( completionBlock ) completionBlock(deviceIsRegistered);
                dispatch_release(completionQueue);
            });
        }];
        if ( error ) NSLog(@"%@", error);
    }];
}

-(NSURL *)syncedDevicesListURL
{
    NSURL *storeURL = self.cloudStoreURL;
    return [storeURL URLByAppendingPathComponent:MCSyncingDevicesListFilename];
}

+(NSString *)deviceIdentifier
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *uniqueId = [defs stringForKey:MCSentinelAppUniqueIdDefault];
    if ( !uniqueId ) {
        uniqueId = [[NSProcessInfo processInfo] globallyUniqueString];
        [defs setObject:uniqueId forKey:MCSentinelAppUniqueIdDefault];
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
            
            // Read in plist
            __block NSMutableDictionary *plist = nil;
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
            [coordinator coordinateReadingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *readURL) {
                plist = [NSMutableDictionary dictionaryWithContentsOfURL:readURL];
            }];
            if ( !plist ) plist = [NSMutableDictionary dictionary];
            
            // Update device list
            NSMutableArray *devices = [[plist objectForKey:@"devices"] mutableCopy];
            if ( !devices ) devices = [NSMutableArray array];
            NSString *deviceId = [self.class deviceIdentifier];
            
            BOOL updated = NO;
            if ( ![devices containsObject:deviceId] ) {
                [devices addObject:deviceId];
                [plist setObject:devices forKey:@"devices"];
                updated = YES;
            }
            
            // Update data set check
            id defaultsDataSetString = [[NSUserDefaults standardUserDefaults] objectForKey:MCCloudResetSentinelSyncDataSetIDUserDefaultKey];
            id dataSetString = [plist objectForKey:@"dataset"];
            if ( !dataSetString ) {
                dataSetString = [[NSProcessInfo processInfo] globallyUniqueString];
                [plist setObject:dataSetString forKey:@"dataset"];
                updated = YES;
            }
            if ( ![dataSetString isEqualToString:defaultsDataSetString] ) {
                [[NSUserDefaults standardUserDefaults] setObject:dataSetString forKey:MCCloudResetSentinelSyncDataSetIDUserDefaultKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
            
            // Write to file
            if ( updated ) {
                [coordinator coordinateWritingItemAtURL:self.cloudStoreURL options:0 error:NULL byAccessor:^(NSURL *newURL) {
                    [[NSFileManager defaultManager] createDirectoryAtURL:newURL withIntermediateDirectories:YES attributes:nil error:NULL];
                }];
                
                [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForReplacing error:NULL byAccessor:^(NSURL *writeURL) {
                    [plist writeToURL:writeURL atomically:NO];
                }];
            }
            
            dispatch_async(completionQueue, ^{
                if ( completionBlock ) completionBlock();
                dispatch_release(completionQueue);
            });
        }];
    });
}

@end
