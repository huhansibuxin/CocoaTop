#import <objc/runtime.h>
#import "Compat.h"
#import "GridCell.h"
#import "CocoaTopPreferences.h"

/*
@interface SmallGraph : UIView
@property (strong) NSArray *dots;
@end

@implementation SmallGraph

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	self.backgroundColor = [UIColor whiteColor]; // clear
	return self;
}

+ (id)graphWithFrame:(CGRect)frame
{
	return [[SmallGraph alloc] initWithFrame:frame];
}

//void draw1PxStroke(CGContextRef context, CGPoint startPoint, CGPoint endPoint, CGColorRef color)
//{
//	CGContextSaveGState(context);
//	CGContextSetLineCap(context, kCGLineCapSquare);
//	CGContextSetLineWidth(context, 1.0);
//	CGContextSetStrokeColorWithColor(context, color);
//	CGContextMoveToPoint(context, startPoint.x + 0.5, startPoint.y + 0.5);
//	CGContextAddLineToPoint(context, endPoint.x + 0.5, endPoint.y + 0.5);
//	CGContextStrokePath(context);
//	CGContextRestoreGState(context);
//}

- (void)drawRect:(CGRect)rect
{
	if (!self.dots) return;
	CGContextRef context = UIGraphicsGetCurrentContext();
	UIColor *color = [UIColor colorWithRed:0.7 green:0.7 blue:1.0 alpha:1.0];
	CGFloat width = self.bounds.size.width,
			height = self.bounds.size.height;
	CGPoint bot = CGPointMake(self.bounds.origin.x + 0.5, self.bounds.origin.y + height + 0.5);

	CGContextSaveGState(context);
	CGContextSetLineCap(context, kCGLineCapSquare);
	CGContextSetLineWidth(context, 1.0);
	CGContextSetStrokeColorWithColor(context, color.CGColor);
	for (NSNumber *val in self.dots) {
//		draw1PxStroke(context, bot, CGPointMake(bot.x, bot.y - (height * [val unsignedIntegerValue] / 100)), color.CGColor);
		CGContextMoveToPoint(context, bot.x, bot.y);
		CGContextAddLineToPoint(context, bot.x, bot.y - (height * [val unsignedIntegerValue] / 200));
		CGContextStrokePath(context);
		bot.x++;
		if (bot.x >= width) break;
	}
	CGContextRestoreGState(context);
}

@end
*/

static bool psIsUserApp(PSProc *proc)
{
	if (!proc.app || !proc.executable)
		return false;
	return [proc.executable rangeOfString:@"/Application/"].location != NSNotFound;
}

// 白色版（真皮）UI 实测基准：498px 宽原图对应 430pt，即 1pt = 1.158px
// 行高 44pt、图标 = 行高 44pt、进程名 18pt、列值 13pt、表头 bold 16pt
static const CGFloat kProcNameFontSize   = 18.0;
static const CGFloat kColumnFontSize     = 13.0;
static const CGFloat kColumnMonoFontSize = 13.0;
static const CGFloat kHeaderFontSize     = 16.0;
static const CGFloat kFooterFontSize     = 12.0;
// 子页面（Summary / Threads / Open files / Open ports）行高只有主界面的 60%，
// 第一列比主界面小四号；主界面 44pt 行高仍保持 18pt 不变
static const CGFloat kTaskNameFontSize   = 14.0;

// 列间竖线：短小、极细（1 物理像素）、隔行显示
static const CGFloat kDividerWidthPx     = 1.0;   // 1 物理像素
static const CGFloat kDividerHeightRatio = 0.34;  // 仅占行高 34%
static const NSInteger kVerticalDividerTag = 8701;

// 四种行底色只构造一次，滚动时只做指针赋值，不再逐行分配 UIColor / block
UIColor *CTCellBackgroundColor(BOOL terminated, BOOL started, BOOL zebra)
{
	static UIColor *termColor, *startColor, *zebraColor, *plainColor;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if (@available(iOS 13, *)) {
			termColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *c) {
				return c.userInterfaceStyle == UIUserInterfaceStyleDark
					? [UIColor colorWithRed:0.5 green:0.12 blue:0.12 alpha:1]
					: [UIColor colorWithRed:1 green:0.7 blue:0.7 alpha:1];
			}];
			startColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *c) {
				return c.userInterfaceStyle == UIUserInterfaceStyleDark
					? [UIColor colorWithRed:0.12 green:0.5 blue:0.12 alpha:1]
					: [UIColor colorWithRed:0.7 green:1 blue:0.7 alpha:1];
			}];
			zebraColor = UIColor.secondarySystemBackgroundColor;
			plainColor = UIColor.systemBackgroundColor;
		} else {
			termColor = [UIColor colorWithRed:1 green:0.7 blue:0.7 alpha:1];
			startColor = [UIColor colorWithRed:0.7 green:1 blue:0.7 alpha:1];
			zebraColor = [UIColor colorWithRed:.95 green:.95 blue:.95 alpha:1];
			plainColor = [UIColor whiteColor];
		}
	});
	return terminated ? termColor : started ? startColor : zebra ? zebraColor : plainColor;
}


@implementation GridTableCell

+ (NSString *)reuseIdWithIcon:(bool)withicon
{
	// 主界面按 %CPU 降序排序，进程每秒都会换到别的行；刷新优化又跳过了 reloadData，
	// cell 对象会一直固定在行号上。若按「当前有没有图标」分成两个复用池，
	// 带图标池的 cell 被复用到无图标进程时会残留旧图标（系统 daemon 显示 CocoaTop/别的插件图标）。
	// 因此统一使用单一复用池，图标完全由 updateWithProc: 按当前进程设置或清空。
	(void)withicon;
	return @"GridTableCell";
}

- (instancetype)initWithIcon:(bool)withicon
{
	self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:[GridTableCell reuseIdWithIcon:withicon]];
	self.accessoryView = [UIView new];
	self.id = 0;
	return self;
}

+ (instancetype)cellWithIcon:(bool)withicon
{
	return [[GridTableCell alloc] initWithIcon:withicon];
}

- (void)configureWithId:(int)id columns:(NSArray *)columns size:(CGSize)size
{
	// Configuration did not change
	if (self.id == id)
		return;
	// 后台无头拉起时 viewWillAppear 不触发 / keyWindow 为 nil，columns 可能尚未初始化。
	// 原来 columns.count-1 在空数组(nil)下会无符号下溢成 NSUIntegerMax，
	// +[NSMutableArray arrayWithCapacity:] 抛异常 -> 未捕获 -> abort()（后台拉起秒闪退的真因）。
	if (columns.count == 0)
		return;
	NSUInteger colCount = columns.count;
	// Remove old views
	if (self.labels)
		for (UILabel *item in self.labels) [item removeFromSuperview];
	if (self.dividers)
		for (UIView *item in self.dividers) [item removeFromSuperview];
	// Create new views
	self.labels = [NSMutableArray arrayWithCapacity:colCount - 1];
	self.dividers = [NSMutableArray arrayWithCapacity:colCount];
	self.extendArgsLabel = [[[CocoaTopPreferences sharedPreferences] objectForKey:@"FullWidthCommandLine"] boolValue];
	self.colorDiffs = [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ColorDiffs"] boolValue];
	self.textLabel.font = [UIFont systemFontOfSize:(size.height > 40 ? kProcNameFontSize : kTaskNameFontSize)];
	if (size.height > 40 && self.extendArgsLabel)
		size.height /= 2;
	NSUInteger totalCol;
	for (PSColumn *col in columns)
		if (col == columns[0]) {
			self.firstColWidth = totalCol = col.width - 5;
			self.textLabel.adjustsFontSizeToFitWidth = !(col.style & ColumnStyleEllipsis);
			if (col.style & ColumnStylePath) {
				if (!(col.style & ColumnStyleTooLong)) self.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
				self.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
			}
		} else {
			// 白色版样式：短小、极细的列间竖线，居中显示；由 RootViewController 按行号隔行显隐
			CGFloat lineW = kDividerWidthPx / [UIScreen mainScreen].scale;
			CGFloat lineH = floor(size.height * kDividerHeightRatio);
			UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(totalCol, (size.height - lineH) / 2, lineW, lineH)];
			divider.tag = kVerticalDividerTag;
            if (@available(iOS 13, *)) {
                divider.backgroundColor = UIColor.separatorColor;
            } else {
                divider.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];
            }
			[self.dividers addObject:divider];
			[self.contentView addSubview:divider];

			//if (col.tag == 4) {
			//	SmallGraph *graph = [SmallGraph graphWithFrame:CGRectMake(totalCol + 1, 0, col.width - 1, size.height)];
			//	graph.tag = 1000;//col.tag;
			//	[self.labels addObject:graph];
			//	[self.contentView addSubview:graph];
			//}
			UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(totalCol + 4, 0, col.width - 8, size.height)];
			label.textAlignment = col.align;
			label.font = col.style & ColumnStyleMonoFont ? [UIFont fontWithName:@"Courier" size:kColumnMonoFontSize] : [UIFont systemFontOfSize:kColumnFontSize];
			label.adjustsFontSizeToFitWidth = !(col.style & ColumnStyleEllipsis);
			if (col.style & ColumnStylePath) label.lineBreakMode = NSLineBreakByTruncatingMiddle;
			label.backgroundColor = [UIColor clearColor];
			label.tag = col.tag + 1;
			[self.labels addObject:label];
			[self.contentView addSubview:label];

			totalCol += col.width;
		}
	if (self.extendArgsLabel) {
		UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(self.firstColWidth, size.height, totalCol - self.firstColWidth, 1)];
		[self.dividers addObject:divider];
		if (@available(iOS 13, *)) {
            divider.backgroundColor = UIColor.secondarySystemBackgroundColor;
        } else {
            divider.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1];
        }
		[self.contentView addSubview:divider];
	}
	self.id = id;
}

// 隔行显示：只切换列间竖线，不影响 FullWidthCommandLine 的横向分隔线
- (void)setVerticalDividersVisible:(BOOL)visible
{
	for (UIView *item in self.dividers)
		if (item.tag == kVerticalDividerTag)
			item.hidden = !visible;
}

- (void)updateWithProc:(PSProc *)proc columns:(NSArray *)columns
{
	self.textLabel.text = proc.name;
	// 三种进程名颜色只构造一次，避免每个可见 cell 每秒都分配 UIColor
	static UIColor *rootNameColor, *userNameColor, *plainNameColor;
	static dispatch_once_t nameColorToken;
	dispatch_once(&nameColorToken, ^{
		rootNameColor  = [UIColor colorWithRed:0.55 green:0.55 blue:1.0 alpha:1.0];
		userNameColor  = [UIColor colorWithRed:0.12 green:0.5 blue:0.12 alpha:1.0];
		plainNameColor = [UIColor blackColor];
	});
	self.textLabel.textColor = proc.uid == 0 ? rootNameColor :
		psIsUserApp(proc) ? userNameColor : plainNameColor;
	self.detailTextLabel.text = [proc.executable stringByAppendingString:proc.args];
	// 必须无条件赋值：proc.icon 为 nil 时要把复用 cell 上的旧图标清掉，
	// 否则排序变动后该行会一直残留上一次（或上一个 app）的图标。
	BOOL needsIcon = proc.icon != nil;
	if (self.imageView.image != proc.icon)
		self.imageView.image = proc.icon;
	if (needsIcon != self.iconShown) {
		self.iconShown = needsIcon;
		// textLabel / detailTextLabel 的起始 x 由 imageView 宽度决定，图标增删后要立即重排
		[self setNeedsLayout];
		// 已在屏幕上的 cell（跳过 reloadData 的轻量刷新路径）需要立刻重排；
		// cellForRowAtIndexPath 新建的 cell 还没父视图，交给 UIKit 后续统一布局即可
		if (self.superview)
			[self layoutIfNeeded];
	}
	for (PSColumn *col in columns)
		if (col != columns[0]) {
			//if (col.tag == 4) {
			//	SmallGraph *graph = (SmallGraph *)[self viewWithTag:1000];//col.tag];
			//	if (graph) { graph.dots = [proc.cpuhistory copy]; [graph setNeedsDisplay]; }
			//} //else {
			UILabel *label = (UILabel *)[self viewWithTag:col.tag + 1];
			if (label) {
				label.text = col.getData(proc);
				if (self.colorDiffs && (col.style & ColumnStyleColor))
					label.textColor = col.getColor(proc);
			}
		}
}

- (void)updateWithSock:(PSSock *)sock columns:(NSArray *)columns
{
	// 子页面不显示图标；统一复用池后显式清空，避免任何残留影响第一列文字缩进
	self.imageView.image = nil;
	self.iconShown = NO;
	self.detailTextLabel.textColor = [UIColor grayColor];
	for (PSColumn *col in columns) {
		UILabel *label;
		if (col != columns[0])
			label = (UILabel *)[self viewWithTag:col.tag + 1];
		else if (col.style & ColumnStyleTooLong) {
			self.textLabel.text = sock.description;
			label = self.detailTextLabel;
		} else {
			self.detailTextLabel.text = nil;
			label = self.textLabel;
		}
		if (label) {
			// The cell label gets a shorter text (sock.name), but the summary page will get the full one
			label.text = col.style & ColumnStyleTooLong ? sock.name : col.getData(sock);
			if (col != columns[0])
			label.textColor = sock.color;
		}
	}
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	CGRect frame;
	NSInteger imageWidth = self.imageView.image ? self.imageView.frame.size.width : 0;
	frame = self.contentView.frame;
		frame.origin.x = 5;
		frame.size.width -= 10;
		self.contentView.frame = frame;
	frame = self.imageView.frame;
		frame.origin.x = 0;
		self.imageView.frame = frame;
	frame = self.textLabel.frame;
		frame.origin.x = imageWidth;
		if (frame.origin.x) frame.origin.x += 5;
		frame.size.width = self.firstColWidth - imageWidth - 5;
		self.textLabel.frame = frame;
	frame = self.detailTextLabel.frame;
		frame.origin.x = imageWidth;
		if (frame.origin.x) frame.origin.x += 5;
		if (!self.extendArgsLabel) frame.size.width = self.firstColWidth - imageWidth - 5;
			else frame.size.width = self.contentView.frame.size.width - imageWidth;
		self.detailTextLabel.frame = frame;
}

@end


@implementation GridHeaderView

- (instancetype)initWithColumns:(NSArray *)columns size:(CGSize)size footer:(bool)footer
{
    if (@available(iOS 6.0, *)) {
        self = [super initWithReuseIdentifier:@"Header"];
        self.backgroundView = [[NSClassFromString(@"_UITableViewHeaderFooterView") alloc] initWithFrame:self.bounds];
    } else {
        self = [super initWithReuseIdentifier:@"Header"];
    }
    
	self.labels = [NSMutableArray arrayWithCapacity:columns.count];
	self.dividers = [NSMutableArray arrayWithCapacity:columns.count];
	NSUInteger totalCol = 0;
	for (PSColumn *col in columns) {
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(totalCol + 2, 0, col.width - 4, size.height)];
		[self.labels addObject:label];
		label.textAlignment = footer && col.getSummary ? col.align : NSTextAlignmentCenter;
		label.font = footer && col != columns[0] ? [UIFont systemFontOfSize:kFooterFontSize] : [UIFont boldSystemFontOfSize:kHeaderFontSize];
		label.adjustsFontSizeToFitWidth = YES;
		label.text = footer ? @"-" : col.name;
        if (@available(iOS 13, *)) {
            label.textColor = [UIColor labelColor];
        } else {
            label.textColor = [UIColor blackColor];
        }
		label.backgroundColor = [UIColor clearColor];
		label.tag = col.tag + 1;
//#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_6_0
        if (@available(iOS 6, *)) {
            [self.contentView addSubview:label];
        } else {
//#else
            [self addSubview:label];
        }
//#endif
		totalCol += col.width;
	}
    
	return self;
}

+ (instancetype)headerWithColumns:(NSArray *)columns size:(CGSize)size
{
	return [[GridHeaderView alloc] initWithColumns:columns size:size footer:NO];
}

+ (instancetype)footerWithColumns:(NSArray *)columns size:(CGSize)size
{
	return [[GridHeaderView alloc] initWithColumns:columns size:size footer:YES];
}

- (void)sortColumnOld:(PSColumn *)oldCol New:(PSColumn *)newCol desc:(BOOL)desc
{
	UILabel *label;
	if (oldCol && oldCol != newCol)
	if ((label = (UILabel *)[self viewWithTag:oldCol.tag + 1])) {
		//
        if (@available(iOS 13, *)) {
            label.textColor = [UIColor labelColor];
        } else {
            label.textColor = [UIColor blackColor];
        }
		label.text = oldCol.name;
	}
	if ((label = (UILabel *)[self viewWithTag:newCol.tag + 1])) {
        label.textColor = self.tintColor;
		label.text = [newCol.name stringByAppendingString:(desc ? @"\u25BC" : @"\u25B2")];
	}
}

- (void)updateSummaryWithColumns:(NSArray *)columns procs:(PSProcArray *)procs
{
	for (PSColumn *col in columns)
		if (col.getSummary) {
			UILabel *label = (UILabel *)[self viewWithTag:col.tag + 1];
			if (label) label.text = col.getSummary(procs);
		}
}

@end
