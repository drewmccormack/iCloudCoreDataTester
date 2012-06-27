
#import <CoreData/CoreData.h>

#import "MCPersistentStoreMigrator.h"

@interface MCPersistentStoreMigrator ()

-(BOOL)save:(NSError **)error;

@end

@implementation MCPersistentStoreMigrator {
    NSMutableDictionary *migratedIDsBySourceID;
    NSMutableDictionary *excludedRelationshipsByEntity;
    NSManagedObjectContext *destinationContext, *sourceContext;
    NSPersistentStore *sourceStore, *destinationStore;
    NSManagedObjectModel *originalManagedObjectModel;
    NSMutableArray *sourceObjectIDsOfUnsavedCounterparts;
}

@synthesize managedObjectModel;
@synthesize destinationStoreURL, sourceStoreURL;
@synthesize sourceStoreOptions, destinationStoreOptions;

-(id)initWithManagedObjectModel:(NSManagedObjectModel *)model sourceStoreURL:(NSURL *)newSourceURL destinationStoreURL:(NSURL *)newDestinationURL
{
    self = [super init];
    if ( self ) {
        destinationContext = nil;
        sourceContext = nil;
        originalManagedObjectModel = model;
        sourceStoreURL = [newSourceURL copy];
        destinationStoreURL = [newDestinationURL copy];
        excludedRelationshipsByEntity = [[NSMutableDictionary alloc] initWithCapacity:10];
        sourceStoreOptions = [NSDictionary dictionaryWithObject:(id)kCFBooleanTrue forKey:NSReadOnlyPersistentStoreOption];
    }
    return self;
}

-(void)setupContexts
{    
    // Destination context
    NSError *error;
    NSPersistentStoreCoordinator *destinationCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    destinationStore = [destinationCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:destinationStoreURL options:destinationStoreOptions error:&error];
    NSAssert(destinationStore != nil, @"Destination Store was nil: %@", error);
    destinationContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    destinationContext.persistentStoreCoordinator = destinationCoordinator;
    
    // Source context
    NSPersistentStoreCoordinator *sourceCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
    sourceStore = [sourceCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:sourceStoreURL options:sourceStoreOptions error:&error];
    NSAssert(sourceStore != nil, @"Source Store was nil: %@", error);
    sourceContext = [[NSManagedObjectContext alloc] init];
    sourceContext.persistentStoreCoordinator = sourceCoordinator;
    
    // Copy metadata
    NSDictionary *metadata = [sourceCoordinator metadataForPersistentStore:sourceStore];
    [destinationCoordinator setMetadata:metadata forPersistentStore:destinationStore];
}

-(void)beginMigration
{
    managedObjectModel = [originalManagedObjectModel copy];
    [self setupContexts];
    migratedIDsBySourceID = [[NSMutableDictionary alloc] initWithCapacity:500];
    sourceObjectIDsOfUnsavedCounterparts = [NSMutableArray arrayWithCapacity:500];
}

-(void)endMigration
{
    sourceStore = nil;
    destinationStore = nil;
    [destinationContext reset];
    [sourceContext reset];
    destinationContext = nil;
    sourceContext = nil;
    migratedIDsBySourceID = nil;
    sourceObjectIDsOfUnsavedCounterparts = nil;
}

-(BOOL)save:(NSError **)error
{
    BOOL success = [self saveDestinationContext:error];
    [destinationContext reset];
    [sourceContext reset];
    return success;
}

-(BOOL)saveDestinationContext:(NSError **)error
{
    // Get permanent object ids
    NSMutableArray *unsavedObjects = [NSMutableArray arrayWithCapacity:sourceObjectIDsOfUnsavedCounterparts.count];
    for ( id sourceID in sourceObjectIDsOfUnsavedCounterparts ) {
        id unsavedObject = [destinationContext objectWithID:[migratedIDsBySourceID objectForKey:sourceID]];
        [unsavedObjects addObject:unsavedObject];
    }
    
    if ( ![destinationContext obtainPermanentIDsForObjects:unsavedObjects error:error] ) return NO;
    
    NSEnumerator *unsavedObjectsEnum = [unsavedObjects objectEnumerator];
    for ( id sourceID in sourceObjectIDsOfUnsavedCounterparts ) {
        NSManagedObject *unsavedObject = [unsavedObjectsEnum nextObject];
        [migratedIDsBySourceID setObject:unsavedObject.objectID forKey:sourceID];
    }
    sourceObjectIDsOfUnsavedCounterparts = [NSMutableArray arrayWithCapacity:500];
     
    // Save
    if ( [destinationContext hasChanges] ) return [destinationContext save:error];
    
    return YES;
}

-(BOOL)migrateEntityWithName:(NSString *)entityName batchSize:(NSUInteger)batchSize save:(BOOL)save error:(NSError **)error
{    
    NSEntityDescription *entity = [managedObjectModel.entitiesByName objectForKey:entityName];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] initWithEntityName:entityName];
    fetch.fetchBatchSize = batchSize;
    fetch.relationshipKeyPathsForPrefetching = entity.relationshipsByName.allKeys;

    NSArray *sourceObjects = [sourceContext executeFetchRequest:fetch error:error];
    if ( !sourceObjects ) return NO;
    
    NSUInteger i = 0;
    while ( i < sourceObjects.count ) {
        @autoreleasepool {
            NSManagedObject *rootObject = [sourceObjects objectAtIndex:i];
            [self migrateRootObject:rootObject];
            i++;
            if ( batchSize && (i % batchSize == 0) && save ) {
                if ( ![self save:error] ) return NO;
            }
        }
    }
    
    BOOL success = YES;
    if ( save ) success = [self save:error];
    
    return success;
}

-(void)snipRelationship:(NSString *)relationshipKey inEntity:(NSString *)entityName
{
    NSMutableSet *excludes = [excludedRelationshipsByEntity objectForKey:entityName];
    if ( !excludes ) excludes = [NSMutableSet set];
    [excludes addObject:relationshipKey];
    [excludedRelationshipsByEntity setObject:excludes forKey:entityName];
}

-(id)migrateRootObject:(NSManagedObject *)rootObject
{
    if ( !rootObject ) return nil;
    
    NSManagedObjectID *counterpartID = [migratedIDsBySourceID objectForKey:rootObject.objectID];
    if ( counterpartID ) return [destinationContext objectWithID:counterpartID];
    
    NSManagedObject *counterpart;
    
    @autoreleasepool {
        // Create counterpart
        NSEntityDescription *entity = rootObject.entity;
        counterpart = [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:destinationContext];
        
        // Add to mapping
        [migratedIDsBySourceID setObject:counterpart.objectID forKey:rootObject.objectID];
        [sourceObjectIDsOfUnsavedCounterparts addObject:rootObject.objectID];
        
        // Set attributes
        for ( NSString *key in entity.attributeKeys ) {
            [counterpart setPrimitiveValue:[rootObject primitiveValueForKey:key] forKey:key];
        }
        
        // Set relationships recursively
        NSSet *exclusions = [excludedRelationshipsByEntity objectForKey:entity.name];
        for ( NSRelationshipDescription *relationDescription in entity.relationshipsByName.allValues ) {
            NSString *key = relationDescription.name;
            if ( [exclusions containsObject:key] ) continue;
            id newValue = nil;
            if ( relationDescription.isToMany ) {
                newValue = [[counterpart primitiveValueForKey:key] mutableCopy];
                for ( NSManagedObject *destinationObject in [rootObject primitiveValueForKey:key] ) {
                    NSManagedObject *destinationCounterpart = [self migrateRootObject:destinationObject];
                    [newValue addObject:destinationCounterpart];
                }
            }
            else {            
                NSManagedObject *destinationObject = [rootObject primitiveValueForKey:key];
                newValue = ( destinationObject ? [self migrateRootObject:destinationObject] : nil );
            }
            
            // If the inverse relationship is snipped, use the full KVC methods, so that it gets set too
            if ( [exclusions containsObject:relationDescription.inverseRelationship.name] ) 
                [counterpart setValue:newValue forKey:key];
            else 
                [counterpart setPrimitiveValue:newValue forKey:key];
        }
    }

    return counterpart;
}

-(BOOL)stitchRelationship:(NSString *)relationshipName inEntity:(NSString *)entityName save:(BOOL)save error:(NSError **)error
{
    const NSInteger batchSize = 100;
    
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:sourceContext];
    NSRelationshipDescription *relationshipDescription = [entity.relationshipsByName objectForKey:relationshipName];
    
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    NSEntityDescription *fetchEntity = [NSEntityDescription entityForName:entityName inManagedObjectContext:sourceContext];
    fetch.entity = fetchEntity;
    fetch.fetchBatchSize = batchSize;
    
    NSArray *sourceObjects = [sourceContext executeFetchRequest:fetch error:error];
    if ( !sourceObjects ) return NO;
    
    NSInteger i = 0;
    for ( NSManagedObject *sourceObject in sourceObjects ) {
        @autoreleasepool {
            NSManagedObjectID *counterpartID = [migratedIDsBySourceID objectForKey:sourceObject.objectID];
            NSAssert(counterpartID != nil, @"Could not find counterpart for object in stitchRelationship:...\nSource Object: %@", sourceObject);
            NSManagedObject *counterpart = (id)[destinationContext objectWithID:counterpartID];
            
            if ( relationshipDescription.isToMany ) {
                id container = [[counterpart valueForKey:relationshipName] mutableCopy];
                for ( NSManagedObject *destinationObject in [sourceObject valueForKey:relationshipName] ) {
                    NSManagedObjectID *destinationCounterpartID = [migratedIDsBySourceID objectForKey:destinationObject.objectID];
                    NSManagedObject *destinationCounterpart = (id)[destinationContext objectWithID:destinationCounterpartID];
                    [container addObject:destinationCounterpart];
                }
                [counterpart setValue:container forKey:relationshipName];
            }
            else {
                NSManagedObject *destinationObject = [sourceObject valueForKey:relationshipName];
                if ( destinationObject ) {
                    NSManagedObjectID *destinationCounterpartID = [migratedIDsBySourceID objectForKey:destinationObject.objectID];
                    NSAssert(destinationCounterpartID != nil, @"A destination object was missing in migration");
                    NSManagedObject *destinationCounterpart = (id)[destinationContext objectWithID:destinationCounterpartID];
                    [counterpart setValue:destinationCounterpart forKey:relationshipName];
                }
            }
            
            if ( ++i % batchSize == 0 && save ) {
                if ( ![self save:error] ) return NO;
            }
        }
    }
    
    BOOL success = YES;
    if ( save ) success = [self save:error];
    
    return success;
}

@end


