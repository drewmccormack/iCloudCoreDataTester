
#import "NSURLExtensions.h"

@implementation NSURL (MCExtensions)

- (void) syncWithCloud:(void (^)(BOOL success, NSError *error))completionBlock {
    
    NSError *error;
    NSNumber *downloaded;
    BOOL success = [self getResourceValue:&downloaded forKey:NSURLUbiquitousItemIsDownloadedKey error:&error];
    if ( !success ) {
        // Resource doesn't exist
        completionBlock(YES, nil);
        return;
    }
    
    if ( !downloaded.boolValue ) {
        NSNumber *downloading;
        BOOL success = [self getResourceValue:&downloading forKey:NSURLUbiquitousItemIsDownloadingKey error:&error];
        if ( !success ) {
            completionBlock(NO, error);
            return;
        }
        
        if ( !downloading.boolValue ) {
            BOOL success = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:self error:&error];
            if ( !success ) {
                completionBlock(NO, error);
                return;
            }
        }
        
        // Download not complete. Schedule another check. 
        double delayInSeconds = 0.1;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        
#if !OS_OBJECT_USE_OBJC
        dispatch_queue_t queue = dispatch_get_current_queue();
        dispatch_retain(queue);
        dispatch_after(popTime, queue, ^{
            [self syncWithCloud:[completionBlock copy]];
            dispatch_release(queue);
        });
#else
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self syncWithCloud:[completionBlock copy]];
        });
#endif
        
    } else {
        completionBlock(YES, nil);
    }
}


@end
