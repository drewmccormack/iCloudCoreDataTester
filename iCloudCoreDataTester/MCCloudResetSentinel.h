//
// Class that can be used to detect resets of an iCloud container.
// It creates and monitors a list of devices in the container.
// If the container is deleted, a reset notification is posted, and
// the delegate is informed.
//
// This class always assumes that iCloud is globally active.
// When creating the sentinel instance, an extra flag can be passed to
// indicate whether cloud syncing is enabled. This setting is independent
// of the global iCloud setting. It allows for the option to have 
// an app that allows syncing to be disabled by the user.
// 
// Methods are provides for checking whether the current device is 
// registered in the list. Once registered, a device cannot be 
// unregistered, even if syncing is disabled. This allows for checking
// whether a device was registered at any point in the past, even
// if it is currently not syncing. 
//
// When syncing becomes enabled, a new sentinel object should be created,
// and the updateDevicesList: method called, to add it to the list.
// 
// Sentinel instances are immutable. When syncing is enabled or disabled, a 
// new sentinel should be created to monitor the new state.
//

#import <Foundation/Foundation.h>

@class MCCloudResetSentinel;

extern NSString * const MCCloudResetSentinelDidDetectResetNotification;
extern NSString * const MCSentinelException;

@protocol MCCloudResetSentinelDelegate <NSObject>

-(void)cloudResetSentinelDidDetectReset:(MCCloudResetSentinel *)sentinel;

@end

@interface MCCloudResetSentinel : NSObject <NSFilePresenter>

@property (nonatomic, readonly, strong) NSURL *cloudStoreURL;
@property (nonatomic, readwrite, weak) id <MCCloudResetSentinelDelegate> delegate;

+(NSString *)devicesListFilename;

-(id)initWithCloudStorageURL:(NSURL *)newURL;

-(void)checkCurrentDeviceRegistration:(void (^)(BOOL deviceIsPresent))completionBlock;
-(void)updateDevicesList:(void (^)(void))completionBlock;

-(void)stopMonitoringDevicesList;

@end
