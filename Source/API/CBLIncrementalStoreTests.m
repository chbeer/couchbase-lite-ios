//
//  CBLIncrementalStoreTests.m
//  CouchbaseLite
//
//  Created by Christian Beer on 01.12.13.
//
//

#import "Test.h"

#import "CouchbaseLite.h"

#import <CoreData/CoreData.h>
#import "CBLIncrementalStore.h"


#if DEBUG

#pragma mark - Helper Classes / Methods

NSManagedObjectModel *CBLISTestCoreDataModel(void);
void CBLISEventuallyDeleteDatabaseNamed(NSString *name);

@class Subentry;
@class File;

@interface Entry : NSManagedObject
@property (nonatomic, retain) NSNumber * check;
@property (nonatomic, retain) NSDate * created_at;
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSString * text2;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) NSDecimalNumber * decimalNumber;
@property (nonatomic, retain) NSNumber * doubleNumber;
@property (nonatomic, retain) NSSet *subentries;
@property (nonatomic, retain) NSSet *files;
@end
@interface Entry (CoreDataGeneratedAccessors)
- (void)addSubentriesObject:(Subentry *)value;
- (void)removeSubentriesObject:(Subentry *)value;
- (void)addSubentries:(NSSet *)values;
- (void)removeSubentries:(NSSet *)values;

- (void)addFilesObject:(File *)value;
- (void)removeFilesObject:(File *)value;
- (void)addFiles:(NSSet *)values;
- (void)removeFiles:(NSSet *)values;
@end

@interface Subentry : NSManagedObject
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) Entry *entry;
@end

@interface File : NSManagedObject
@property (nonatomic, retain) NSString * filename;
@property (nonatomic, retain) NSData * data;
@property (nonatomic, retain) Entry *entry;
@end

@interface NSManagedObjectID (CBLIncrementalStore)
- (NSString*) couchbaseLiteIDRepresentation;
@end

#pragma mark - Tests

/** Test case that tests create, request, update and delete of Core Data objects. */
TestCase(CBLIncrementalStoreCRUD)
{
    NSError *error;
    
    NSString *databaseName = @"test-crud";
    
    CBLISEventuallyDeleteDatabaseNamed(databaseName);
    
    NSManagedObjectModel *model = CBLISTestCoreDataModel();
    NSManagedObjectContext *context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    Assert(context, @"Context could not be created: %@", error);
    
    CBLIncrementalStore *store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");
    
    CBLDatabase *database = store.database;
    
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    
    // cut off seconds as they are not encoded in date values in DB
    NSDate *createdAt = [NSDate dateWithTimeIntervalSince1970:(long)[NSDate new].timeIntervalSince1970];
    NSString *text = @"Test";
    
    entry.created_at = createdAt;
    entry.text = text;
    entry.check = @NO;
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    CBLDocument *doc = [database documentWithID:[entry.objectID couchbaseLiteIDRepresentation]];
    AssertEqual(entry.text, [doc propertyForKey:@"text"]);
    
    NSDate *date1 = entry.created_at;
    NSDate *date2 = [CBLJSON dateWithJSONObject:[doc propertyForKey:@"created_at"]];
    int diffInSeconds = (int)floor([date1 timeIntervalSinceDate:date2]);
    AssertEq(diffInSeconds, 0);
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);
    
    
    entry.check = @(YES);
    
    success = [context save:&error];
    Assert(success, @"Could not save context after update: %@", error);
    
    doc = [database documentWithID:[entry.objectID couchbaseLiteIDRepresentation]];
    AssertEqual(entry.check, [doc propertyForKey:@"check"]);
    AssertEqual(@(YES), [doc propertyForKey:@"check"]);
    
    
    NSManagedObjectID *objectID = entry.objectID;
    
    // tear down context to reload from DB
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    database = store.database;
    
    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert((entry != nil), @"Could not re-load entry (%@)", error);
    AssertEqual(entry.text, text);
    AssertEqual(entry.created_at, createdAt);
    AssertEqual(entry.check, @YES);
    
    
    [context deleteObject:entry];
    success = [context save:&error];
    Assert(success, @"Could not save context after deletion: %@", error);
    
    doc = [database documentWithID:[objectID couchbaseLiteIDRepresentation]];
    Assert([doc isDeleted], @"Document not marked as deleted after deletion");
}

/** Test case that tests the integration between Core Data and CouchbaseLite. */
TestCase(CBLIncrementalStoreCBLIntegration)
{
    NSError *error;
    
    NSString *databaseName = @"test-crud";
    
    CBLISEventuallyDeleteDatabaseNamed(databaseName);
    
    NSManagedObjectModel *model = CBLISTestCoreDataModel();
    NSManagedObjectContext *context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    Assert(context, @"Context could not be created: %@", error);
    
    CBLIncrementalStore *store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");
    
    CBLDatabase *database = store.database;

    // cut off seconds as they are not encoded in date values in DB
    NSString *text = @"Test";
    NSNumber *number = @23;
    
    // first test creation and storage of Core Data entities
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    
    entry.text = text;
    entry.check = @NO;
    entry.number = number;
    
    Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                       inManagedObjectContext:context];
    subentry.number = @123;
    subentry.text = @"abc";
    [entry addSubentriesObject:subentry];
    
    File *file = [NSEntityDescription insertNewObjectForEntityForName:@"File"
                                               inManagedObjectContext:context];
    file.filename = @"abc.png";
    file.data = [text dataUsingEncoding:NSUTF8StringEncoding];
    [entry addFilesObject:file];
    
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    NSManagedObjectID *entryID = entry.objectID;
    NSManagedObjectID *subentryID = subentry.objectID;
    NSManagedObjectID *fileID = file.objectID;

    // get document from Couchbase to check correctness
    CBLDocument *entryDoc = [database documentWithID:[entryID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *entryProperties = [entryDoc.properties mutableCopy];
    AssertEqual(entry.text, [entryProperties objectForKey:@"text"]);
    AssertEqual(text, [entryProperties objectForKey:@"text"]);
    AssertEqual(entry.check, [entryProperties objectForKey:@"check"]);
    AssertEqual(entry.number, [entryProperties objectForKey:@"number"]);
    AssertEqual(number, [entryProperties objectForKey:@"number"]);

    CBLDocument *subentryDoc = [database documentWithID:[subentryID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *subentryProperties = [subentryDoc.properties mutableCopy];
    AssertEqual(subentry.text, [subentryProperties objectForKey:@"text"]);
    AssertEqual(subentry.number, [subentryProperties objectForKey:@"number"]);

    CBLDocument *fileDoc = [database documentWithID:[fileID couchbaseLiteIDRepresentation]];
    NSMutableDictionary *fileProperties = [fileDoc.properties mutableCopy];
    AssertEqual(file.filename, [fileProperties objectForKey:@"filename"]);
    
    CBLAttachment *attachment = [fileDoc.currentRevision attachmentNamed:@"data"];
    Assert(attachment != nil, @"Unable to load attachment");
    AssertEqual(file.data, attachment.content);
    

    // now change the properties in CouchbaseLite and check if those are available in Core Data
    [entryProperties setObject:@"different text" forKey:@"text"];
    [entryProperties setObject:@NO forKey:@"check"];
    [entryProperties setObject:@42 forKey:@"number"];
    id revisions = [entryDoc putProperties:entryProperties error:&error];
    Assert(revisions != nil, @"Couldn't persist changed properties in CBL: %@", error);
    Assert(error == nil, @"Couldn't persist changed properties in CBL: %@", error);
    
    entry = (Entry*)[context existingObjectWithID:entryID error:&error];
    Assert(entry != nil, @"Couldn load entry: %@", error);

    // if one of the following fails, make sure you compiled the CBLIncrementalStore with CBLIS_NO_CHANGE_COALESCING=1
    AssertEqual(entry.text, [entryProperties objectForKey:@"text"]);
    AssertEqual(entry.check, [entryProperties objectForKey:@"check"]);
    AssertEqual(entry.number, [entryProperties objectForKey:@"number"]);
    
}

TestCase(CBLIncrementalStoreCreateAndUpdate)
{
    NSError *error;
    
    NSString *databaseName = @"test-createandupdate";
    
    CBLISEventuallyDeleteDatabaseNamed(databaseName);
    
    NSManagedObjectModel *model = CBLISTestCoreDataModel();
    NSManagedObjectContext *context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    Assert(context, @"Context could not be created: %@", error);
    
    CBLIncrementalStore *store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");
    
    
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    
    entry.check = @(YES);
    
    success = [context save:&error];
    Assert(success, @"Could not save context after update: %@", error);
    

    Subentry *subentry = [NSEntityDescription insertNewObjectForEntityForName:@"Subentry"
                                                       inManagedObjectContext:context];
    
    subentry.text = @"Subentry abc";
    
    [entry addSubentriesObject:subentry];
    
    success = [context save:&error];
    Assert(success, @"Could not save context after update 2: %@", error);
    
    subentry.number = @123;
    
    success = [context save:&error];
    Assert(success, @"Could not save context after update 3: %@", error);
    
    NSManagedObjectID *objectID = entry.objectID;
    
    // tear down and re-init for checking that data got saved
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    
    entry = (Entry*)[context existingObjectWithID:objectID error:&error];
    Assert(entry, @"Entry could not be loaded: %@", error);
    AssertEq(entry.subentries.count, (unsigned int)1);
    AssertEqual([entry.subentries valueForKeyPath:@"text"], [NSSet setWithObject:@"Subentry abc"]);
    AssertEqual([entry.subentries valueForKeyPath:@"number"], [NSSet setWithObject:@123]);
}

TestCase(CBLIncrementalStoreFetchrequest)
{
    NSError *error;
    
    NSString *databaseName = @"test-fetchrequest";
    
    CBLISEventuallyDeleteDatabaseNamed(databaseName);
    
    NSManagedObjectModel *model = CBLISTestCoreDataModel();
    NSManagedObjectContext *context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    Assert(context, @"Context could not be created: %@", error);
    
    CBLIncrementalStore *store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");

    
    Entry *entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                                 inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test";
    entry.check = @(YES);
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Entry"];
    
    fetchRequest.resultType = NSCountResultType;
    
    NSArray *result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, (NSUInteger)1);
    Assert([result[0] intValue] > 0, @"Database should contain more than zero entries (if the testCreateAndUpdate was run)");
    
    NSUInteger count = [result[0] intValue];
    
    fetchRequest.resultType = NSDictionaryResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSDictionary class]], @"Results are not NSDictionaries");
    
    
    fetchRequest.resultType = NSManagedObjectIDResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSManagedObjectID class]], @"Results are not NSManagedObjectIDs");
    
    
    fetchRequest.resultType = NSManagedObjectResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, count);
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");
    
    //// Predicate
    
    entry = [NSEntityDescription insertNewObjectForEntityForName:@"Entry"
                                          inManagedObjectContext:context];
    entry.created_at = [NSDate new];
    entry.text = @"Test2";
    
    success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"text == 'Test2'"];
    
    fetchRequest.resultType = NSCountResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    AssertEq(result.count, (NSUInteger)1);
    Assert([result[0] intValue] > 0, @"Database should contain more than zero entries (if the testCreateAndUpdate was run)");
    
    count = [result[0] intValue];
    
    fetchRequest.resultType = NSDictionaryResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSDictionary class]], @"Results are not NSDictionaries");
    
    fetchRequest.resultType = NSManagedObjectIDResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSManagedObjectID class]], @"Results are not NSManagedObjectIDs");
    
    fetchRequest.resultType = NSManagedObjectResultType;
    
    result = [context executeFetchRequest:fetchRequest error:&error];
    Assert(result.count == count, @"Fetch request should return same result count as number fetch");
    Assert([result[0] isKindOfClass:[NSManagedObject class]], @"Results are not NSManagedObjects");
}

TestCase(CBLIncrementalStoreAttachments)
{
    NSError *error;
    
    NSString *databaseName = @"test-attachments";
    
    CBLISEventuallyDeleteDatabaseNamed(databaseName);
    
    NSManagedObjectModel *model = CBLISTestCoreDataModel();
    NSManagedObjectContext *context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    Assert(context, @"Context could not be created: %@", error);
    
    CBLIncrementalStore *store = context.persistentStoreCoordinator.persistentStores[0];
    Assert(store, @"Context doesn't have any store?!");

    CBLDatabase *database = store.database;

    
    File *file = [NSEntityDescription insertNewObjectForEntityForName:@"File"
                                               inManagedObjectContext:context];
    file.filename = @"test.txt";
    
    NSData *data = [@"Test. Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    file.data = data;
    
    BOOL success = [context save:&error];
    Assert(success, @"Could not save context: %@", error);
    
    CBLDocument *doc = [database documentWithID:[file.objectID couchbaseLiteIDRepresentation]];
    Assert(doc != nil, @"Document should not be nil");
    AssertEqual(file.filename, [doc propertyForKey:@"filename"]);
    
    CBLAttachment *att = [doc.currentRevision attachmentNamed:@"data"];
    Assert(att != nil, @"Attachmant should be created");
    
    NSData *content = att.content;
    Assert(content != nil, @"Content should be loaded");
    AssertEq(content.length, data.length);
    AssertEqual(content, data);
    
    NSManagedObjectID *fileID = file.objectID;
    
    // tear down the context to reload from disk
    file = nil;
    context = [CBLIncrementalStore createManagedObjectContextWithModel:model databaseName:databaseName error:&error];
    
    file = (File*)[context existingObjectWithID:fileID error:&error];
    Assert(file != nil, @"File should not be nil (%@)", error);
    AssertEqual(file.data, data);
}

#pragma mark -
#pragma mark - Test Core Data Model

NSAttributeDescription *CBLISAttributeDescription(NSString *name, BOOL optional, NSAttributeType type, id defaultValue);
NSRelationshipDescription *CBLISRelationshipDescription(NSString *name, BOOL optional, BOOL toMany, NSDeleteRule deletionRule, NSEntityDescription *destinationEntity);

NSAttributeDescription *CBLISAttributeDescription(NSString *name, BOOL optional, NSAttributeType type, id defaultValue)
{
    NSAttributeDescription *attribute = [NSAttributeDescription new];
    [attribute setName:name];
    [attribute setOptional:optional];
    [attribute setAttributeType:type];
    if (defaultValue) {
        [attribute setDefaultValue:defaultValue];
    }
    return attribute;
}
NSRelationshipDescription *CBLISRelationshipDescription(NSString *name, BOOL optional, BOOL toMany, NSDeleteRule deletionRule, NSEntityDescription *destinationEntity)
{
    NSRelationshipDescription *relationship = [NSRelationshipDescription new];
    [relationship setName:name];
    [relationship setOptional:optional];
    [relationship setMinCount:optional ? 0 : 1];
    [relationship setMaxCount:toMany ? 0 : 1];
    [relationship setDeleteRule:deletionRule];
    [relationship setDestinationEntity:destinationEntity];
    return relationship;
}
NSManagedObjectModel *CBLISTestCoreDataModel(void)
{
    NSManagedObjectModel *model = [NSManagedObjectModel new];
    
    NSEntityDescription *entry = [NSEntityDescription new];
    [entry setName:@"Entry"];
    [entry setManagedObjectClassName:@"Entry"];
    
    NSEntityDescription *file = [NSEntityDescription new];
    [file setName:@"File"];
    [file setManagedObjectClassName:@"File"];

    NSEntityDescription *subentry = [NSEntityDescription new];
    [subentry setName:@"Subentry"];
    [subentry setManagedObjectClassName:@"Subentry"];
    
    NSRelationshipDescription *entryFiles = CBLISRelationshipDescription(@"files", YES, YES, NSCascadeDeleteRule, file);
    NSRelationshipDescription *entrySubentries = CBLISRelationshipDescription(@"subentries", YES, YES, NSCascadeDeleteRule, subentry);
    NSRelationshipDescription *fileEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    NSRelationshipDescription *subentryEntry = CBLISRelationshipDescription(@"entry", YES, NO, NSNullifyDeleteRule, entry);
    
    [entryFiles setInverseRelationship:fileEntry];
    [entrySubentries setInverseRelationship:subentryEntry];
    [fileEntry setInverseRelationship:entryFiles];
    [subentryEntry setInverseRelationship:entrySubentries];

    [entry setProperties:@[
                           CBLISAttributeDescription(@"check", YES, NSBooleanAttributeType, nil),
                           CBLISAttributeDescription(@"created_at", YES, NSDateAttributeType, nil),
                           CBLISAttributeDescription(@"decimalNumber", YES, NSDecimalAttributeType, @(0.0)),
                           CBLISAttributeDescription(@"doubleNumber", YES, NSDoubleAttributeType, @(0.0)),
                           CBLISAttributeDescription(@"number", YES, NSInteger16AttributeType, @(0)),
                           CBLISAttributeDescription(@"text", YES, NSStringAttributeType, nil),
                           CBLISAttributeDescription(@"text2", YES, NSStringAttributeType, nil),
                           entryFiles,
                           entrySubentries
                           ]];
    
    [file setProperties:@[
                          CBLISAttributeDescription(@"data", YES, NSBinaryDataAttributeType, nil),
                          CBLISAttributeDescription(@"filename", YES, NSStringAttributeType, nil),
                          fileEntry
                          ]];
    
    [subentry setProperties:@[
                              CBLISAttributeDescription(@"number", YES, NSInteger32AttributeType, @(0)),
                              CBLISAttributeDescription(@"text", YES, NSStringAttributeType, nil),
                              subentryEntry
                              ]];
    
    [model setEntities:@[entry, file, subentry]];
    
    return model;
}

@implementation Entry
@dynamic check, created_at, text, text2, number, decimalNumber, doubleNumber, subentries, files;
@end

@implementation Subentry
@dynamic text, number, entry;
@end

@implementation File
@dynamic filename, data, entry;
@end

void CBLISEventuallyDeleteDatabaseNamed(NSString *name)
{
    NSError *error;
    CBLDatabase *database = [[CBLManager sharedInstance] databaseNamed:name error:&error];
    if (database) {
        BOOL success = [database deleteDatabase:&error];
        Assert(success, @"Could not delete database named %@", name);
    }
}

#endif
