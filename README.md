# The Best Lua Objective C wrapper

This is intended to speed up development with Lua in Objective C. It's kind of slow if you're passing values in and out of it in a huge loop (has to convert to NS\* and back a bunch of times) but it's really useful if you just need to get one thing into the interpreter or get one thing out of the interpreter. You don't even need to understand how the stack works!

BTW, Lua 5.2.2 is already included in here so you can just drag-n-drop this into your project.

Here's some sample code to get you started:

```objc
LuaInterpreter *lua = [LuaInterpreter sharedInstance];
//^ you can also do an alloc init
//  if you want multiple sessions

[lua openDefaultLibs]; //opens default libs (like print and math)

[lua runString:@"square = function(x) return x*x end"];
[lua runFile:@"lol.lua"];

LuaFunction *square = [lua getGlobal:@"square"];

NSArray *result = [square callWithArguments:@[@(5)] numExpectedResults:1];
NSLog(@"%@", result[0]); //25

//overwriting square still preserves the function
[lua setGlobal:@"square" value:@(3)];

NSString *newSquare = [lua getGlobal:@"square"];

NSNumber *result2 = [square callWithArgument:newSquare];
NSLog(@"%@", result2); //9

[square invalidate]; //remove function from registry
id x = [square call];
NSLog(@"%@", x); //(null)

NSMutableDictionary *table = [NSMutableDictionary dictionary];
table[@"test"] = @(5);

[lua setGlobal:@"test_table" value:table];

[lua runString:@"print(test_table.test)"]; //5

static int l_test(lua_State *L)
{
    printf("l_test was called\n");
    return 0;
}

LuaFunction *test = [LuaFunction functionWithCFunction:l_test andInterpreter:lua];
[lua setGlobal:@"test" value:test];
[lua runString:@"test()"]; //l_test was called

//change environment
static int l_newprint(lua_State *L)
{
    NSString *arg = [NSString stringWithUTF8String:lua_tostring(L, -1)];
    printf("Length: %d", (int)arg.length);
    return 0;
}

LuaFunction *sandboxed = [LuaFunction functionWithLuaCode:@"print(\"test\")" andInterpreter:lua];
LuaFunction *newprint = [LuaFunction functionWithCFunction:l_newprint andInterpreter:lua];
sandboxed.environment = [[LuaTable alloc] initWithInterpreter:lua andDictionary:@{@"print": newprint}];
[sandboxed call]; //Length: 4


```

Also, if you have a class with the LuaObject protocol, you can implement these two:
```objc
-(NSDictionary *)luaRepresentation;
//^ make sure to set the value of RW_LUA_OBJECT_CLASS
//  in the dict to the name of the class (so it can
//  be converted back into an Obj-C class)

-(id)initWithLuaTable:(NSDictionary *)table;
```
And you can turn your Obj C classes back and forth into Lua tables!

## Issues

Really shitty debugging. Doesn't print Lua errors out. I'm working on this.

## License

MIT License. It's at the top of any of the source code files.

Lua itself uses an [MIT License](http://www.lua.org/license.html), too.
