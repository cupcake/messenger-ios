//
//  Contact.h
//  Messages
//
//  Created by Jesse Stuart on 7/28/13.
//  Copyright (c) 2013 Boolean Cupcake, LLC. All rights reserved.
//

@import Foundation;
@import CoreData;

@class Conversation, Message, TCPostManagedObject;

@interface Contact : NSManagedObject

@property(nonatomic, retain) NSData *avatar;
@property(nonatomic) BOOL avatarIsSigil;
@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *entityURI;
@property(nonatomic, retain) NSString *sectionName;
@property(nonatomic, retain) NSSet *conversations;
@property(nonatomic, retain) NSSet *messages;
@property(nonatomic, retain) TCPostManagedObject *relationshipPost;

+ (void)syncRelationships;

@end

@interface Contact (CoreDataGeneratedAccessors)

- (void)addConversationsObject:(Conversation *)value;
- (void)removeConversationsObject:(Conversation *)value;
- (void)addConversations:(NSSet *)values;
- (void)removeConversations:(NSSet *)values;

- (void)addMessagesObject:(Message *)value;
- (void)removeMessagesObject:(Message *)value;
- (void)addMessages:(NSSet *)values;
- (void)removeMessages:(NSSet *)values;

@end
