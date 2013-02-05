
#import <Foundation/Foundation.h>

@interface NSURL (MCExtensions)

- (void) syncWithCloud:(void (^)(BOOL success, NSError *error))completionBlock;

@end
