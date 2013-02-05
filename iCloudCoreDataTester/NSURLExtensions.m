
#import "NSURLExtensions.h"

@implementation NSURL (MCExtensions)

-(void)syncWithCloud:(void (^)(BOOL success, NSError *error))completionBlock {
    
    NSError *error;
    NSNumber *downloaded;
    BOOL success = [self getResourceValue:&downloaded forKey:NSURLUbiquitousItemIsDownloadedKey error:&error];
    if ( !success ) {
        // Resource doesn't exist
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(YES, nil);
        });
        return;
    }
    
    if ( !downloaded.boolValue ) {
        NSNumber *downloading;
        BOOL success = [self getResourceValue:&downloading forKey:NSURLUbiquitousItemIsDownloadingKey error:&error];
        if ( !success ) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completionBlock(YES, nil);
            });
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
        dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self syncWithCloud:completionBlock];
        });
        
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(YES, nil);
        });
    }
}

@end
