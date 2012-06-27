//
//  MCPersistentStoreMigrator.h
//  Mental Case 2
//
//  Created by Drew McCormack on 6/22/12.
//  Copyright (c) 2012 The Mental Faculty. All rights reserved.
//

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

@class MCManagedObjectContext;

@interface MCPersistentStoreMigrator : NSObject

@property (nonatomic, readonly) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, readonly) NSURL *destinationStoreURL, *sourceStoreURL;
@property (nonatomic, readwrite, copy) NSDictionary *sourceStoreOptions, *destinationStoreOptions;

-(id)initWithManagedObjectModel:(NSManagedObjectModel *)model sourceStoreURL:(NSURL *)sourceURL destinationStoreURL:(NSURL *)destinationURL;

-(void)beginMigration;
-(void)endMigration;

-(BOOL)migrateEntityWithName:(NSString *)entityName batchSize:(NSUInteger)batchSize save:(BOOL)save error:(NSError **)error;

-(void)snipRelationship:(NSString *)relationshipKey inEntity:(NSString *)entityName;
-(BOOL)stitchRelationship:(NSString *)relationshipName inEntity:(NSString *)entityName save:(BOOL)save error:(NSError **)error;

@end
