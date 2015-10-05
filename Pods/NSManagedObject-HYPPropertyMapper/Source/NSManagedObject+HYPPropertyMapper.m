#import "NSManagedObject+HYPPropertyMapper.h"

#import "NSString+HYPNetworking.h"
#import "NSDate+HYPPropertyMapper.h"
#import "NSManagedObject+HYPPropertyMapperHelpers.h"

static NSString * const HYPPropertyMapperNestedAttributesKey = @"attributes";
static NSString * const HYPPropertyMapperDestroyKey = @"destroy";

@implementation NSManagedObject (HYPPropertyMapper)

#pragma mark - Public methods

- (void)hyp_fillWithDictionary:(NSDictionary *)dictionary {
    for (__strong NSString *key in dictionary) {

        id value = [dictionary objectForKey:key];

        BOOL isReservedKey = ([[NSManagedObject reservedAttributes] containsObject:key]);
        if (isReservedKey) {
            key = [self prefixedAttribute:key];
        }

        NSAttributeDescription *attributeDescription = [self attributeDescriptionForRemoteKey:key];
        if (attributeDescription) {
            NSString *localKey = attributeDescription.name;

            BOOL valueExists = (value &&
                                ![value isKindOfClass:[NSNull class]]);
            if (valueExists) {
                id processedValue = [self valueForAttributeDescription:attributeDescription
                                                      usingRemoteValue:value];

                BOOL valueHasChanged = (![[self valueForKey:localKey] isEqual:processedValue]);
                if (valueHasChanged) {
                    [self setValue:processedValue forKey:localKey];
                }
            } else if ([self valueForKey:localKey]) {
                [self setValue:nil forKey:localKey];
            }
        }
    }
}

- (NSDictionary *)hyp_dictionary {
    return [self hyp_dictionaryWithDateFormatter:[self defaultDateFormatter] usingRelationshipType:HYPPropertyMapperRelationshipTypeNested];
}

- (NSDictionary *)hyp_dictionaryUsingRelationshipType:(HYPPropertyMapperRelationshipType)relationshipType {
    return [self hyp_dictionaryWithDateFormatter:[self defaultDateFormatter] usingRelationshipType:relationshipType];
}

- (NSDictionary *)hyp_dictionaryWithDateFormatter:(NSDateFormatter *)formatter {
    return [self hyp_dictionaryWithDateFormatter:formatter usingRelationshipType:HYPPropertyMapperRelationshipTypeNested];
}

- (NSDictionary *)hyp_dictionaryWithDateFormatter:(NSDateFormatter *)formatter usingRelationshipType:(HYPPropertyMapperRelationshipType)relationshipType {
    NSMutableDictionary *managedObjectAttributes = [NSMutableDictionary new];

    for (id propertyDescription in self.entity.properties) {
        if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attributeDescription = (NSAttributeDescription *)propertyDescription;
            if (attributeDescription.attributeType != NSTransformableAttributeType) {
                id value = [self valueForKey:attributeDescription.name];
                BOOL nilOrNullValue = (!value ||
                                       [value isKindOfClass:[NSNull class]]);
                if (nilOrNullValue) {
                    value = [NSNull null];
                } else if ([value isKindOfClass:[NSDate class]]) {
                    value = [formatter stringFromDate:value];
                }

                NSString *remoteKey = [self remoteKeyForAttributeDescription:attributeDescription];
                managedObjectAttributes[remoteKey] = value;
            }
        } else if ([propertyDescription isKindOfClass:[NSRelationshipDescription class]] &&
                   relationshipType != HYPPropertyMapperRelationshipTypeNone) {
            NSString *relationshipName = [propertyDescription name];

            id relationships = [self valueForKey:relationshipName];
            BOOL isToOneRelationship = (![relationships isKindOfClass:[NSSet class]]);
            if (isToOneRelationship) {
                NSDictionary *attributesForToOneRelationship = [self attributesForToOneRelationship:relationships
                                                                                   relationshipName:relationshipName
                                                                              usingRelationshipType:relationshipType];
                [managedObjectAttributes addEntriesFromDictionary:attributesForToOneRelationship];
            } else {
                NSDictionary *attributesForToManyRelationship = [self attributesForToManyRelationship:relationships
                                                                                     relationshipName:relationshipName
                                                                                usingRelationshipType:relationshipType];
                [managedObjectAttributes addEntriesFromDictionary:attributesForToManyRelationship];
            }
        }
    }

    return [managedObjectAttributes copy];
}

- (NSDictionary *)attributesForRelationship:(NSManagedObject *)relationship
                           relationshipName:(NSString *)relationshipName
                           relationshipType:(HYPPropertyMapperRelationshipType)relationshipType {
    NSMutableDictionary *attributes = [NSMutableDictionary new];
    for (NSAttributeDescription *propertyDescription in [relationship.entity properties]) {
        if ([propertyDescription isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeDescription *attributeDescription = (NSAttributeDescription *)propertyDescription;
            id value = [relationship valueForKey:attributeDescription.name];
            if (value) {
                NSString *attribute = propertyDescription.name;
                NSString *localKey = HYPPropertyMapperDefaultLocalValue;
                BOOL attributeIsKey = ([localKey isEqualToString:attribute]);

                NSString *key;
                if (attributeIsKey) {
                    key = HYPPropertyMapperDefaultRemoteValue;
                } else if ([attribute isEqualToString:HYPPropertyMapperDestroyKey] &&
                           relationshipType == HYPPropertyMapperRelationshipTypeNested) {
                    key = [NSString stringWithFormat:@"_%@", HYPPropertyMapperDestroyKey];
                } else {
                    key = [attribute hyp_remoteString];
                }

                attributes[key] = value;
            }
        }
    }

    return attributes;
}

- (NSDictionary *)attributesForToOneRelationship:(NSManagedObject *)relationship
                                relationshipName:(NSString *)relationshipName
                           usingRelationshipType:(HYPPropertyMapperRelationshipType)relationshipType {
    NSMutableDictionary *attributesForToOneRelationship = [NSMutableDictionary new];
    NSDictionary *attributes = [self attributesForRelationship:relationship
                                              relationshipName:relationshipName
                                              relationshipType:relationshipType];
    if (attributes.count > 0) {
        NSString *key = [relationshipName hyp_remoteString];
        if (relationshipType == HYPPropertyMapperRelationshipTypeNested) {
            key = [NSString stringWithFormat:@"%@_%@", [relationshipName hyp_remoteString], HYPPropertyMapperNestedAttributesKey];
        }

        [attributesForToOneRelationship setValue:attributes forKey:key];
    }

    return attributesForToOneRelationship;
}

- (NSDictionary *)attributesForToManyRelationship:(NSSet *)relationships
                                 relationshipName:(NSString *)relationshipName
                            usingRelationshipType:(HYPPropertyMapperRelationshipType)relationshipType {
    NSMutableDictionary *attributesForToManyRelationship = [NSMutableDictionary new];
    NSUInteger relationIndex = 0;
    NSMutableDictionary *relationsDictionary = [NSMutableDictionary new];
    NSMutableArray *relationsArray = [NSMutableArray new];
    for (NSManagedObject *relation in relationships) {
        NSDictionary *attributes = [self attributesForRelationship:relation
                                                  relationshipName:relationshipName
                                                  relationshipType:relationshipType];

        if (attributes.count > 0) {
            if (relationshipType == HYPPropertyMapperRelationshipTypeArray) {
                [relationsArray addObject:attributes];
            } else if (relationshipType == HYPPropertyMapperRelationshipTypeNested) {
                NSString *relationIndexString = [NSString stringWithFormat:@"%lu", (unsigned long)relationIndex];
                relationsDictionary[relationIndexString] = attributes;
                relationIndex++;
            }
        }
    }

    if (relationshipType == HYPPropertyMapperRelationshipTypeArray) {
        [attributesForToManyRelationship setValue:relationsArray forKey:[relationshipName hyp_remoteString]];
    } else if (relationshipType == HYPPropertyMapperRelationshipTypeNested) {
        NSString *nestedAttributesPrefix = [NSString stringWithFormat:@"%@_%@", [relationshipName hyp_remoteString], HYPPropertyMapperNestedAttributesKey];
        [attributesForToManyRelationship setValue:relationsDictionary forKey:nestedAttributesPrefix];
    }

    return attributesForToManyRelationship;
}

#pragma mark - Private

- (NSDateFormatter *)defaultDateFormatter {
    static NSDateFormatter *_dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dateFormatter = [NSDateFormatter new];
        _dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    });
    
    return _dateFormatter;
}

@end
