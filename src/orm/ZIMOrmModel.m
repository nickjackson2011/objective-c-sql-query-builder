/*
 * Copyright 2011 Ziminji
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 * 
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import "ZIMDaoConnection.h"
#import "ZIMOrmModel.h"
#import "ZIMSqlDeleteStatement.h"
#import "ZIMSqlInsertStatement.h"
#import "ZIMSqlSelectStatement.h"
#import "ZIMSqlUpdateStatement.h"

@implementation ZIMOrmModel

#if !defined(ZIMOrmDataSource)
// Define this pre-processing instruction "ZIMOrmDataSource" in <project-name>_Prefix.pch 
#define ZIMOrmDataSource		@"defaultdb.sqlite"
#endif

- (id) init {
	if (self = [super init]) {
		_primaryKey = [NSSet setWithObject: @"pk"];
		_autoIncremented = YES;
		_saved = nil;
	}
	return self;
}

- (void) dealloc {
	[super dealloc];
}

- (void) delete {
	if ((_primaryKey != nil) && ([_primaryKey count] > 0)) {
		ZIMSqlDeleteStatement *sql = [[ZIMSqlDeleteStatement alloc] init];
		[sql table: [[self class] table]];
		for (NSString *column in _primaryKey) {
			id value = [self valueForKey: column];
			if (value == nil) {
				[sql release];
				@throw [NSException exceptionWithName: @"ZIMOrmException" reason: [NSString stringWithFormat: @"Failed to delete record because no value has been assigned to the '%@' column.", column] userInfo: nil];
			}
			[sql where: column operator: ZIMSqlOperatorEqualTo value: value];
		}
		[ZIMDaoConnection dataSource: [[self class] dataSource] execute: [sql statement]];
		[sql release];
		_saved = nil;
	}
	else {
		@throw [NSException exceptionWithName: @"ZIMOrmException" reason: @"Failed to delete record because no primary key has been declared." userInfo: nil];
	}
}

- (void) save {
	if ((_primaryKey != nil) && ([_primaryKey count] > 0)) {
		ZIMDaoConnection *connection = [[ZIMDaoConnection alloc] initWithDataSource: [[self class] dataSource]];
		[connection execute: @"BEGIN IMMEDIATE TRANSACTION;"];
		NSMutableDictionary *columns = [[NSMutableDictionary alloc] initWithDictionary: [[self class] columns]];
		NSString *hashCode = [self hashCode];
		BOOL doInsert = (hashCode == nil);
		if (!doInsert) {
			doInsert = ((_saved == nil) || ![_saved isEqualToString: hashCode]);
			if (doInsert) {
				ZIMSqlSelectStatement *select = [[ZIMSqlSelectStatement alloc] init];
				[select column: @"1" alias: @"IsFound"];
				[select from: [[self class] table]];
				for (NSString *column in _primaryKey) {
					[select where: column operator: ZIMSqlOperatorEqualTo value: [self valueForKey: column]];
				}
				[select limit: 1];
				NSArray *records = [connection query: [select statement]];
				doInsert = ([records count] == 0);
				[select release];
			}
			if (!doInsert) {
				for (NSString *column in _primaryKey) {
					[columns removeObjectForKey: column];
				}
				if ([columns count] > 0) {
					ZIMSqlUpdateStatement *update = [[ZIMSqlUpdateStatement alloc] init];
					[update table: [[self class] table]];
					for (NSString *column in columns) {
						[update column: column value: [self valueForKey: column]];
					}
					for (NSString *column in _primaryKey) {
						NSString *value = [self valueForKey: column];
						if (value == nil) {
							[update release];
							[columns release];
							[connection release];
							@throw [NSException exceptionWithName: @"ZIMOrmException" reason: [NSString stringWithFormat: @"Failed to save record because column '%@' has no assigned value.", column] userInfo: nil];
						}
						[update where: column operator: ZIMSqlOperatorEqualTo value: value];
					}
					[connection execute: [update statement]];
					[update release];
				}
			}
		}
		if (doInsert) {
			if (_autoIncremented && (hashCode == nil)) {
				for (NSString *column in _primaryKey) {
					[columns removeObjectForKey: column];
				}
			}
			if ([columns count] > 0) {
				ZIMSqlInsertStatement *insert = [[ZIMSqlInsertStatement alloc] init];
				[insert table: [[self class] table]];
				for (NSString *column in columns) {
					NSString *value = [self valueForKey: column];
					if ([_primaryKey containsObject: column] && (value == nil)) {
						[insert release];
						[columns release];
						[connection release];
						@throw [NSException exceptionWithName: @"ZIMOrmException" reason: [NSString stringWithFormat: @"Failed to save record because column '%@' has no assigned value.", column] userInfo: nil];
					}
					[insert column: column value: value];
				}
				NSNumber *result = [connection execute: [insert statement]];
				if (_autoIncremented) {
					[self setValue: result forKey: [[_primaryKey allObjects] objectAtIndex: 0]];
				}
				[insert release];
				_saved = [self hashCode];
			}
		}
		[columns release];
		[connection execute: @"COMMIT TRANSACTION;"];
		[connection release];
	}
	else {
		@throw [NSException exceptionWithName: @"ZIMOrmException" reason: @"Failed to save record because no primary key has been declared." userInfo: nil];
	}
}

- (NSString *) hashCode {
	NSMutableString *primaryKey = [[NSMutableString alloc] init];
	for (NSString *column in _primaryKey) {
		id value = [self valueForKey: column];
		if (value == nil) {
			[primaryKey release];
			return nil;
		}
		[primaryKey appendFormat: @"%@=%@", column, value];
	}
	const char *cString = [primaryKey UTF8String];
	[primaryKey release];
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(cString, strlen(cString), digest);
	NSMutableString *hashKey = [NSMutableString stringWithCapacity: CC_SHA1_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
		[hashKey appendFormat: @"%02X", digest[i]];
	}
	return [hashKey lowercaseString];
}

+ (NSString *) dataSource {
	return ZIMOrmDataSource;
}

+ (NSString *) table {
	return NSStringFromClass([self class]);
}

+ (NSDictionary *) columns {
	// TODO get instance variables from super classes as well to allow further subclassing
	
	NSSet *configurations = [[NSSet alloc] initWithObjects: @"_primaryKey", @"_autoIncremented", @"_saved", nil];
	
	unsigned int columnCount;
	
	Ivar *vars = class_copyIvarList([self class], &columnCount);
	
	int capacity = columnCount - [configurations count];
	
	NSMutableDictionary *columns = [[[NSMutableDictionary alloc] initWithCapacity: capacity] autorelease];
	
	for (int i = 0; i < columnCount; i++) {
		Ivar var = vars[i];
		
		NSString *columnName = [NSString stringWithUTF8String: ivar_getName(var)];
		
		if (![configurations containsObject: columnName]) {
			NSString *columnType = [NSString stringWithUTF8String: ivar_getTypeEncoding(var)]; // http://developer.apple.com/library/mac/#documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
			[columns setObject: columnType forKey: columnName];
		}
	}
	
	free(vars);
	
	[configurations release];
	
	return columns;
}

@end
