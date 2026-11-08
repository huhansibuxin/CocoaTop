#import "CocoaTopPreferences.h"
#import "roothide.h"

#define COCOATOP_PREFERENCES_PLIST jbroot(@"/var/mobile/Library/Preferences/ru.domo.cocoatop64.plist")

static NSDictionary *CocoaTopDefaultPreferences(void)
{
	return @{
		// 默认列顺序：命令行 / %CPU / 常驻内存 / 进程运行时间(ΣTime) / Mach 任务状态 /
		// Mach 任务角色 / 原始进程标志 / 物理内存占用 / 用户 ID / 线程数 / 进程 ID / Mach 端口
		// 与 RootViewController.m 的 registerDefaults 必须保持一致，否则重装后配置会变
		@"Columns" : @[@0, @3, @7, @29, @5, @20, @6, @24, @9, @12, @1, @13],
		@"UpdateInterval" : @"1",
		@"FullWidthCommandLine" : @NO,
		@"ColorDiffs" : @YES,
		@"AutoJumpNewProcess" : @NO,
		@"FirstColumnStyle" : @"Bundle Identifier",
		@"ShowHeader" : @YES,
		@"ShowFooter" : @YES,
		@"ShortenPaths" : @YES,
		// 与 RootViewController.m 的 registerDefaults 保持一致：默认按 %CPU 使用率降序
		@"SortColumn" : @3, @"SortDescending" : @YES,
		@"FilterColumn" : @0,
		@"ProcInfoMode" : @0,
		@"Mode0SortColumn" : @1001, @"Mode0SortDescending" : @NO,
		@"Mode1SortColumn" : @2000, @"Mode1SortDescending" : @NO,
		@"Mode2SortColumn" : @3002, @"Mode2SortDescending" : @YES,
		@"Mode3SortColumn" : @4001, @"Mode3SortDescending" : @NO,
	};
}

@interface CocoaTopPreferences ()
@property (strong) NSMutableDictionary *values;
@end

@implementation CocoaTopPreferences

+ (instancetype)sharedPreferences
{
	static CocoaTopPreferences *preferences;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		preferences = [CocoaTopPreferences new];
	});
	return preferences;
}

- (instancetype)init
{
	self = [super init];
	if (self)
		_values = [[NSDictionary dictionaryWithContentsOfFile:COCOATOP_PREFERENCES_PLIST] mutableCopy] ?: [NSMutableDictionary dictionary];
	return self;
}

- (id)objectForKey:(NSString *)key
{
	return self.values[key];
}

- (void)setObject:(id)value forKey:(NSString *)key
{
	if (value)
		self.values[key] = value;
	else
	[self.values removeObjectForKey:key];
	[self.values writeToFile:COCOATOP_PREFERENCES_PLIST atomically:YES];
}

- (void)removeObjectForKey:(NSString *)key
{
	[self setObject:nil forKey:key];
}

- (void)registerDefaults:(NSDictionary *)defaults
{
	[defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
		if (!self.values[key])
			self.values[key] = value;
	}];
	[self.values writeToFile:COCOATOP_PREFERENCES_PLIST atomically:YES];
}

- (void)reset
{
	self.values = [CocoaTopDefaultPreferences() mutableCopy];
	[self.values writeToFile:COCOATOP_PREFERENCES_PLIST atomically:YES];
}

@end
