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

#import "LuaInterpreter.h"

static void stackDump (lua_State *L) {
    printf("{");
    int i;
    int top = lua_gettop(L);
    for (i = 1; i <= top; i++) {  /* repeat for each level */
        int t = lua_type(L, i);
        switch (t) {
                
            case LUA_TSTRING:  /* strings */
                printf("\"%s\"", lua_tostring(L, i));
                break;
                
            case LUA_TBOOLEAN:  /* booleans */
                printf(lua_toboolean(L, i) ? "true" : "false");
                break;
                
            case LUA_TNUMBER:  /* numbers */
                printf("%g", lua_tonumber(L, i));
                break;
                
            default:  /* other values */
                printf("<%s>", lua_typename(L, t));
                break;
                
        }
        if(i < top)
            printf(",  ");  /* put a separator */
    }
    printf("}\n");  /* end the listing */
}

@implementation LuaInterpreter
@synthesize state=L;


static LuaInterpreter *_shared;
static NSMutableArray *_instances;

+(LuaInterpreter *)sharedInstance
{
    if(_shared == nil)
    {
        _shared = [[LuaInterpreter alloc] init];
    }
    return _shared;
}

+(LuaInterpreter *)interpreterWithState:(lua_State *)state
{
    for(LuaInterpreter *interpreter in _instances)
    {
        if(interpreter.state == state) return interpreter;
    }
    return nil;
}

-(id)init
{
    if(self == [super init])
    {
        L = luaL_newstate();
        
        
        self.validInstances = @[].mutableCopy;
        
        if(_instances == nil)
            _instances = @[].mutableCopy;
        
        [_instances addObject:self];
    }
    return self;
}

-(void)dealloc
{
    lua_close(L);
    [_instances removeObject:self];
    for(LuaInstance *instance in self.validInstances)
    {
        [instance invalidate];
    }
}

-(void)openDefaultLibs
{
    luaL_openlibs(L);
}

-(NSObject<LuaObject> *)luaObjectFromTable:(NSDictionary *)table
{
    NSString *className = table[RW_LUA_OBJECT_CLASS];
    if(className == nil || ![className isKindOfClass:NSString.class]) return nil;
    
    
    Class class = NSClassFromString(className);
    if(class == nil) return nil;
    
    id obj = [class alloc];
    if([obj conformsToProtocol:@protocol(LuaObject)] && [obj respondsToSelector:@selector(initWithLuaTable:)])
    {
        return [obj initWithLuaTable:table];
    }
    return nil;
}

-(id)getGlobal:(NSString *)name instance:(BOOL)isInstance
{
    lua_getglobal(L, [name UTF8String]);
    
    id obj;
    if(isInstance)
        obj = [self getStackInstanceAtIndex:-1];
    else
        obj = [self getStackObjectAtIndex:-1];
    lua_pop(L,1);
    return obj;
}

-(id)getGlobal:(NSString *)name
{
    return [self getGlobal:name instance:false];
}

-(LuaInstance *)getGlobalInstance:(NSString *)name
{
    return [self getGlobal:name instance:true];
}

-(BOOL)runString:(NSString *)code
{
    luaL_loadstring(L, [code UTF8String]);
    lua_pcall(L, 0, 0, 0);
    return true;
}

-(BOOL)runFile:(NSString *)filename
{
    return luaL_dofile(L, [filename UTF8String]);
}

-(void)removeInstance:(LuaInstance *)instance
{
    if([self.validInstances containsObject:instance])
    {
        [self.validInstances removeObject:instance];
    }
    luaL_unref(L, LUA_REGISTRYINDEX, instance.registryIndex);
}

-(BOOL)setGlobal:(NSString *)name value:(id)obj
{
    BOOL okay = [self pushObj:obj];
    if(!okay)
    {
        if([obj isKindOfClass:LuaInstance.class])
        {
            [NSException raise:@"Object is not in LuaInterpreter!" format:@"tried to set global %@ (%@) in invalid context", name, [obj class]];
        }
        return okay;
    }
    
    lua_setglobal(L, [name UTF8String]);
    
    return okay;
}

-(void)printStack
{
    stackDump(L);
}

-(id)convertInstance:(LuaInstance *)instance
{
    if(instance.type == LUA_TNUMBER || instance.type == LUA_TSTRING || instance.type == LUA_TTABLE)
    {
        [self pushObj:instance];
        id obj = [self getStackObjectAtIndex:-1];
        lua_pop(L, 1);
        return obj;
    }
    return nil;
}

//---------------------------------------------------------
#pragma mark Private functions
//---------------------------------------------------------

-(BOOL)pushObj:(id)obj
{
    
    if([obj isKindOfClass:NSString.class])
    {
        lua_pushstring(L, [obj UTF8String]);
    }
    else if([obj isKindOfClass:NSNumber.class])
    {
        lua_pushnumber(L, [obj doubleValue]);
    }
    else if([obj isKindOfClass:NSArray.class])
    {
        if(![self pushArray:obj createTable:true])
        {
            return false;
        }
    }
    else if([obj isKindOfClass:NSDictionary.class])
    {
        if(![self pushDictionary:obj])
        {
            return false;
        }
    }
    else if([obj conformsToProtocol:@protocol(LuaObject)] && [obj respondsToSelector:@selector(luaRepresentation)])
    {
        obj = [obj luaRepresentation];
        if(![self pushDictionary:obj])
        {
            return false;
        }
    }
    else if([obj isKindOfClass:LuaInstance.class])
    {
        if([obj interpreter] != self || ![self.validInstances containsObject:obj])
        {
            return false;
        }
        lua_rawgeti(L, LUA_REGISTRYINDEX, [obj registryIndex]);
    }
    else
    {
        return false;
    }
    return true;
}

-(BOOL)pushDictionary:(NSDictionary *)dictionary
{
    lua_newtable(L);
    for(NSString *key in dictionary)
    {
        id obj = [dictionary objectForKey:key];
        
        lua_pushstring(L, [key UTF8String]);
        if([self pushObj:obj])
        {
            lua_settable(L, -3);
        }
        else
        {
            lua_pop(L, 2);
            return false;
        }
    }
    return true;
}

-(BOOL)pushArray:(NSArray *)array createTable:(BOOL)shouldCreateTable
{
    if(shouldCreateTable)
    {
        lua_newtable(L);
    }
    BOOL result = true;
    int pushed = 0;
    for(id obj in array)
    {
        if(shouldCreateTable)
        {
            lua_pushnumber(L, pushed + 1);
        }
        result = [self pushObj:obj];
        if(!result)
        {
            if(shouldCreateTable)
            {
                lua_pop(L, 1);
                pushed = 1;
            }
            break;
        }
        if(shouldCreateTable)
            lua_rawset(L, -3);
        
        pushed++;
    }
    if(!result)
    {
        lua_pop(L, pushed);
    }
    return result;
}

-(id)getStackInstanceAtIndex:(int)index
{
    lua_pushvalue(L, index);
    
    LuaInstance *instance;
    
    if(lua_isfunction(L, -1))
    {
        instance = [LuaFunction alloc];
    }
    else if(lua_istable(L, -1))
    {
        instance = [LuaTable alloc];
    }
    else
    {
        instance = [LuaInstance alloc];
    }
    
    instance = [instance initWithInterpreter:self];
    instance.registryIndex = luaL_ref(L, LUA_REGISTRYINDEX);
    [self.validInstances addObject:instance];
    
    return instance;
}

-(id)getStackObjectAtIndex:(int)index
{
    if(lua_isnumber(L, index))
    {
        return @(lua_tonumber(L, index));
    }
    else if(lua_isstring(L, index))
    {
        const char *str = lua_tostring(L, index);
        return [NSString stringWithUTF8String:str];
    }
    else if(lua_istable(L, index))
    {
        NSDictionary *table = [self getTableFromStackAtIndex:(int)index];
        
        id obj = [self luaObjectFromTable:table];
        if(obj == nil)
            return table;
        return obj;
    }
    else if(lua_isfunction(L, index))
    {
        return [self getStackInstanceAtIndex:index];
    }
    
    return nil;
}

-(NSDictionary *)getTableFromStackAtIndex:(int)index
{
    NSMutableDictionary *table = [[NSMutableDictionary alloc] init];
    
    if (lua_istable(L, index))
    {
        
        lua_pushvalue(L, index); //put table at top of stack
        lua_pushnil(L);
        
        while (lua_next(L, -2) != 0) //pop old key, push next key, push value
        {
            // stack now contains: -1 => value; -2 => key; -3 => table
            // copy the key so that lua_tostring does not modify the original
            lua_pushvalue(L, -2);
            NSString *key = [NSString stringWithUTF8String:lua_tostring(L, -1)];
            lua_pop(L, 1);
            id obj = [self getStackObjectAtIndex:-1];
            lua_pop(L, 1); //pop value
            [table setObject:obj forKey:key];
            
        }
        lua_pop(L, 1); //pop duplicate table
        return table;
    }
    else
    {
        return nil;
    }
}


@end

//---------------------------------------------------------
#pragma mark LuaInstance
//---------------------------------------------------------

@implementation LuaInstance
@synthesize interpreter=_interpreter, isValid=_isValid;

-(id)initWithInterpreter:(LuaInterpreter *)interpreter
{
    if(self == [super init])
    {
        _interpreter = interpreter;
    }
    return self;
}

-(id)init
{
    return [self initWithInterpreter:nil];
}

-(BOOL)isValid
{
    return _isValid && self.interpreter != nil && [_interpreter.validInstances containsObject:self];
}

-(int)type
{
    if(!self.isValid) return LUA_TNIL;
    lua_rawgeti(_interpreter.state, LUA_REGISTRYINDEX, self.registryIndex);
    int type = lua_type(_interpreter.state, -1);
    lua_pop(_interpreter.state, 1);
    return type;
}

-(void)setRegistryIndex:(int)registryIndex
{
    _isValid = true;
    _registryIndex = registryIndex;
}

-(BOOL)invalidate
{
    LuaInterpreter *lua= self.interpreter;
    if(self.isValid)
    {
        [lua removeInstance:self];
        return true;
    }
    _isValid = false;
    return false;
}

@end


//---------------------------------------------------------
#pragma mark LuaTable
//---------------------------------------------------------
@implementation LuaTable

-(id)initWithInterpreter:(LuaInterpreter *)interpreter andDictionary:(NSDictionary *)dictionary
{
    if(self == [super initWithInterpreter:interpreter])
    {
        if(dictionary != nil)
        {
            [self.interpreter pushObj:dictionary];
            LuaInstance *instance = [self.interpreter getStackInstanceAtIndex:-1];
            lua_pop(self.interpreter.state, 1);
            self.registryIndex = instance.registryIndex;
            [self.interpreter.validInstances addObject:self];
            [self.interpreter.validInstances removeObject:instance];
        }
    }
    return self;
}

-(id)initWithInterpreter:(LuaInterpreter *)interpreter
{
    return [self initWithInterpreter:interpreter andDictionary:nil];
}

-(void)checkValid
{
    if(self.isValid) return;
    
    lua_newtable(self.interpreter.state);
    self.registryIndex = luaL_ref(self.interpreter.state, LUA_REGISTRYINDEX);
    if(![self.interpreter.validInstances containsObject:self])
        [self.interpreter.validInstances addObject:self];
}

-(NSDictionary *)toDictionary
{
    if(!self.isValid) return @{};
    
    [self.interpreter pushObj:self];
    NSDictionary *dict = [self.interpreter getStackObjectAtIndex:-1];
    lua_pop(self.interpreter.state, 1);
    return dict;
}

-(LuaInstance *)valueForKey:(NSString *)key
{
    [self checkValid];
    
    [self.interpreter pushObj:self];
    [self.interpreter pushObj:key];
    lua_gettable(self.interpreter.state, -2);
    LuaInstance *instance = [self.interpreter getStackInstanceAtIndex:-1];
    lua_pop(self.interpreter.state, 2);
    return instance;
}

-(void)setValue:(id)value forKey:(NSString *)key
{
    [self checkValid];
    
    [self.interpreter pushObj:self];
    [self.interpreter pushObj:key];
    [self.interpreter pushObj:value];
    
    lua_settable(self.interpreter.state, -3);
    lua_pop(self.interpreter.state, 1);
}

@end



//---------------------------------------------------------
#pragma mark LuaFunction
//---------------------------------------------------------

@implementation LuaFunction

#pragma mark static methods

+(LuaFunction *)functionWithCFunction:(lua_CFunction)cfunction andInterpreter:(LuaInterpreter *)interpreter
{
    if(interpreter == nil) interpreter = [LuaInterpreter sharedInstance];
    
    //push the function to the stack and get let the interpreter convert it to a LuaFunction
    lua_pushcfunction(interpreter.state, cfunction);
    LuaFunction *function = [interpreter getStackObjectAtIndex:-1];
    lua_pop(interpreter.state, 1);
    return function;
}

+(LuaFunction *)functionWithCFunction:(lua_CFunction)cfunction
{
    return [LuaFunction functionWithCFunction:cfunction andInterpreter:nil];
}

+(LuaFunction *)functionWithLuaCode:(NSString *)code andInterpreter:(LuaInterpreter *)interpreter
{
    if(interpreter == nil) interpreter = [LuaInterpreter sharedInstance];
    
    luaL_loadstring(interpreter.state, [code UTF8String]);
    LuaFunction *function = [interpreter getStackInstanceAtIndex:-1];
    lua_pop(interpreter.state, 1);
    return function;
}

+(LuaFunction *)functionWithLuaCode:(NSString *)code
{
    return [LuaFunction functionWithLuaCode:code andInterpreter:nil];
}

+(LuaFunction *)functionFromFile:(NSString *)filename andInterpreter:(LuaInterpreter *)interpreter
{
    if(interpreter == nil) interpreter = [LuaInterpreter sharedInstance];
    
    luaL_loadfile(interpreter.state, [filename UTF8String]);
    LuaFunction *function = [interpreter getStackInstanceAtIndex:-1];
    lua_pop(interpreter.state, 1);
    return function;
}

+(LuaFunction *)functionFromFile:(NSString *)filename
{
    return [LuaFunction functionFromFile:filename andInterpreter:nil];
}

#pragma mark instance methods

-(void)setEnvironment:(LuaTable *)table
{
    [self.interpreter pushObj:self];
    [self.interpreter pushObj:table];
    lua_setupvalue(self.interpreter.state, -2, 1);
    lua_pop(self.interpreter.state, 1);
}

-(LuaTable *)environment
{
    [self.interpreter pushObj:self];
    lua_getupvalue(self.interpreter.state, -1, 1);
    LuaTable *table = [self.interpreter getStackInstanceAtIndex:-1];
    lua_pop(self.interpreter.state, 2);
    return table;
}

-(NSArray *)callWithArguments:(NSArray *)arguments numExpectedResults:(int)numExpectedResults
{
    if(!self.isValid) return nil;
    
    LuaInterpreter *lua= self.interpreter;
    lua_State *L = lua.state;
    
    lua_rawgeti(L, LUA_REGISTRYINDEX, self.registryIndex);
    if(arguments != nil && ![lua pushArray:arguments createTable:false])
    {
        return nil;
    }
    lua_pcall(L, (int)arguments.count, numExpectedResults, 0);
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:numExpectedResults];
    for(int i = 0; i < numExpectedResults; i++)
    {
        int stackIndex = i - numExpectedResults;
        id obj = [lua getStackObjectAtIndex:stackIndex];
        if(obj != nil)
            [result addObject:obj];
    }
    lua_pop(L, numExpectedResults);
    return result;
}
-(id)callWithArguments:(NSArray *)arguments
{
    NSArray *result = [self callWithArguments:arguments numExpectedResults:1];
    
    if(result.count > 0)
        return result[0];
    else
        return nil;
}

-(id)callWithArgument:(id)argument
{
    NSArray *arguments = argument == nil?nil:@[argument];
    return [self callWithArguments:arguments];
}
-(id)call
{
    return [self callWithArguments:nil];
}

@end






