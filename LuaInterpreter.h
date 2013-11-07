/*
 Copyright (c) 2013 Reed Weichler
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

#import <Foundation/Foundation.h>
#import "lua.h"
#import "lauxlib.h"
#import "lualib.h"

#import "LuaObject.h"

//---------------------------------------------------------
#pragma mark LuaInterpreter
//---------------------------------------------------------

@class LuaInstance; //forward declaration
@interface LuaInterpreter : NSObject

+(LuaInterpreter *)sharedInstance;
+(LuaInterpreter *)interpreterWithState:(lua_State *)state;

@property (nonatomic) lua_State *state;

@property (nonatomic, strong) NSMutableArray *validInstances;
-(void)removeInstance:(LuaInstance *)instance;

-(void)openDefaultLibs;

-(id)getStackObjectAtIndex:(int)index;
-(id)getStackInstanceAtIndex:(int)index;

-(NSObject<LuaObject> *)luaObjectFromTable:(NSDictionary *)table;
-(id)getGlobal:(NSString *)name;
-(id)getGlobalInstance:(NSString *)name;

-(BOOL)setGlobal:(NSString *)name value:(id)obj;

-(BOOL)runString:(NSString *)code;
-(BOOL)runFile:(NSString *)filename;

-(id)convertInstance:(LuaInstance *)instance; //converts LuaInstance to NSObject version if possible

-(void)printStack;

@end


//---------------------------------------------------------
#pragma mark LuaInstance
//---------------------------------------------------------
@interface LuaInstance : NSObject

-(id)initWithInterpreter:(LuaInterpreter *)interpreter;

@property (nonatomic) int registryIndex;
@property (nonatomic) LuaInterpreter *interpreter;
@property (nonatomic, readonly) BOOL isValid;
@property (nonatomic, readonly) int type;

-(BOOL)invalidate;

@end

//---------------------------------------------------------
#pragma mark LuaTable
//---------------------------------------------------------
@interface LuaTable: LuaInstance

-(id)initWithInterpreter:(LuaInterpreter *)interpreter andDictionary:(NSDictionary *)dictionary;

-(NSDictionary *)toDictionary;

-(LuaInstance *)valueForKey:(NSString *)key;
-(void)setValue:(id)value forKey:(NSString *)key;

@end

//---------------------------------------------------------
#pragma mark LuaFunction
//---------------------------------------------------------

@interface LuaFunction : LuaInstance

+(LuaFunction *)functionWithCFunction:(lua_CFunction)cfunction;
+(LuaFunction *)functionWithCFunction:(lua_CFunction)cfunction andInterpreter:(LuaInterpreter *)interpreter;

+(LuaFunction *)functionWithLuaCode:(NSString *)code;
+(LuaFunction *)functionWithLuaCode:(NSString *)code andInterpreter:(LuaInterpreter *)interpreter;

+(LuaFunction *)functionFromFile:(NSString *)filename;
+(LuaFunction *)functionFromFile:(NSString *)filename andInterpreter:(LuaInterpreter *)interpreter;

@property (nonatomic) LuaTable *environment;

-(id)call;
-(id)callWithArguments:(NSArray *)arguments;
-(id)callWithArgument:(id)argument;
-(NSArray *)callWithArguments:(NSArray *)arguments numExpectedResults:(int)numExpectedResults;

@end