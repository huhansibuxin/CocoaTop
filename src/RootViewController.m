#import "Compat.h"
#import "RootViewController.h"
#import "SockViewController.h"
#import "THtmlViewController.h"
#import "Setup.h"
#import "SetupColumns.h"
#import "GridCell.h"
#import "Column.h"
#import "Proc.h"
#import "ProcArray.h"
#import "AppDelegate.h"
#import "CocoaTopPreferences.h"
#import "roothide.h"

#define NTSTAT_PREQUERY_INTERVAL	0.1
#define ROOT_HIDE_CONFIG_PLIST jbroot(@"/var/mobile/Library/RootHide/RootHideConfig.plist")

@implementation UIScrollView (AdjustInset)

-(UIEdgeInsets)realUIContentInset {
    if (@available(iOS 11.0, *)) {
        //UIEdgeInsets system = self.adjustedContentInset;
        //UIEdgeInsets user = self.contentInset;
        //return UIEdgeInsetsMake(system.top + user.top, system.left + user.left, system.bottom + user.bottom, system.right + user.right);
        return self.adjustedContentInset;
    } else {
        return self.contentInset;
    }
}

@end

@implementation RootViewController
{
	GridHeaderView *header;
	GridHeaderView *footer;
	UISearchBar *filter;
	PSProcArray *procs;
	NSTimer *timer;
	UILabel *statusLabel;
	NSArray *columns;
	PSColumn *sortColumn;
	PSColumn *filterColumn;
	BOOL sortDescending;
	BOOL fullScreen;
	BOOL refreshPaused;		// 暂停按钮状态：仅当前页面有效，离开再返回自动恢复刷新
	CGFloat timerInterval;
	NSUInteger configId;
	NSString *configChange;
	pid_t selectedPid;
    UIUserInterfaceSizeClass lastHorizationWindowSizeClass;
    CGFloat lastHorizationWindowWidth;
}

- (void)popupMenuTappedItem:(NSInteger)item
{
	UIViewController* view = nil;
	switch (item) {
	case 0: view = [[SetupViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
	case 1: view = [[SetupColsViewController alloc] initWithStyle:UITableViewStyleGrouped]; break;
	case 2: view = [[HtmlViewController alloc] initWithURL:@"guide" title:@"Quick Guide"]; break;
	case 3: view = [[HtmlViewController alloc] initWithURL:@"story" title:@"The Story"]; break;
	}
	if (view)
		[self.navigationController pushViewController:view animated:YES];
}

- (UINavigationController*)navigationController {
    if ([self.parentViewController isKindOfClass: [RootTabMaskController class]]) {
        return self.parentViewController.navigationController;
    } else {
        return [super navigationController];
    }
}

- (UINavigationItem *)navigationItem {
    if ([self.parentViewController isKindOfClass: [RootTabMaskController class]]) {
        return self.parentViewController.navigationItem;
    } else {
        return [super navigationItem];
    }
}

- (IBAction)hideShowNavBar:(UIGestureRecognizer *)gestureRecognizer
{
	if (!gestureRecognizer || gestureRecognizer.state == UIGestureRecognizerStateEnded) {
		fullScreen = !self.navigationController.navigationBarHidden;
		// This "scrolls" tableview so that it doesn't actually move when the bars disappear
		if (!fullScreen) {			// Show navbar & scrollbar (going out of fullscreen)
			[[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
			[self.navigationController setNavigationBarHidden:NO animated:NO];
		}
		CGSize size = [UIApplication sharedApplication].statusBarFrame.size;
		CGFloat slide = MIN(size.width, size.height) +
			self.navigationController.navigationBar.frame.size.height +
			([[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShowHeader"] boolValue] ? self.tableView.sectionHeaderHeight : 0);
		CGPoint contentOffset = self.tableView.contentOffset;
		contentOffset.y += fullScreen ? -slide : slide;
		[self.tableView setContentOffset:contentOffset animated:NO];
		if (fullScreen) {			// Hide navbar & scrollbar (entering fullscreen)
			[self.navigationController setNavigationBarHidden:YES animated:NO];
			[[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
		}
		[self.tableView reloadData];
//		[timer fire];
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleDefault;
	bool isPhone = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone;

//	self.wantsFullScreenLayout = YES;
	[self popupMenuWithItems:@[@"Settings", @"Columns", @"Quick Guide", @"About"] selected:-1 aligned:UIControlContentHorizontalAlignmentLeft];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"UIButtonBarHamburger"] style:UIBarButtonItemStylePlain
		target:self action:@selector(popupMenuToggle)];
	self.navigationItem.rightBarButtonItem = [self refreshToggleItem];
	statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width - (isPhone ? 80 : 150), 40)];
	statusLabel.backgroundColor = [UIColor clearColor];
	self.navigationItem.leftBarButtonItems = @[self.navigationItem.leftBarButtonItem, [[UIBarButtonItem alloc] initWithCustomView:statusLabel]];

	UITapGestureRecognizer *twoTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideShowNavBar:)];
	twoTap.numberOfTouchesRequired = 2;
	[self.tableView addGestureRecognizer:twoTap];

	// 长按复制进程可执行路径
	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	longPress.minimumPressDuration = 0.5;
	[self.tableView addGestureRecognizer:longPress];

	filter = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 0)];
	filter.autocapitalizationType = UITextAutocapitalizationTypeNone;
	filter.autocorrectionType = UITextAutocorrectionTypeNo;
	filter.spellCheckingType = UITextSpellCheckingTypeNo;
    [filter setBackgroundImage:[UIImage new]];
//	filter.returnKeyType = UIReturnKeyDone;
//	filter.showsCancelButton = YES;
//	filter.showsSearchResultsButton = NO;
	filter.delegate = self; 
	[filter sizeToFit];
    
    if (@available(iOS 13, *)) {
        self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    } else {
        self.tableView.backgroundColor = [UIColor colorWithWhite:.75 alpha:1];
    }
    self.tableView.rowHeight = 44;
    self.tableView.sectionHeaderHeight = 23;
    self.tableView.sectionFooterHeight = 23;
	self.tableView.tableHeaderView = filter;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame: CGRectZero];

	self.tableView.sectionHeaderHeight = self.tableView.sectionHeaderHeight * 3 / 2;
//#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_7_0
    if (@available(iOS 7, *)) {
        [self.tableView setSeparatorInset:UIEdgeInsetsZero];
    }
//#endif
	[[CocoaTopPreferences sharedPreferences] registerDefaults:@{
		// 与 CocoaTopPreferences.m 的 CocoaTopDefaultPreferences 保持一致
		@"Columns" : @[@0, @3, @7, @29, @5, @20, @6, @24, @9, @12, @1, @13],
		@"UpdateInterval" : @"1",
		@"FullWidthCommandLine" : @NO,
		@"ColorDiffs" : @YES,
		@"AutoJumpNewProcess" : @NO,
		@"FirstColumnStyle" : @"Bundle Identifier",
		@"ShowHeader" : @YES,
		@"ShowFooter" : @YES,
		@"ShortenPaths" : @YES,
		@"SortColumn" : @3,         @"SortDescending" : @YES,		// Main page (按 %CPU 使用率降序, 表头显示 %▼)
		@"FilterColumn" : @0,
		@"ProcInfoMode" : @0,
		@"Mode0SortColumn" : @1001, @"Mode0SortDescending" : @NO,	// Summary (by initial column order)
		@"Mode1SortColumn" : @2000, @"Mode1SortDescending" : @NO,	// Threads (by thread id)
		@"Mode2SortColumn" : @3002, @"Mode2SortDescending" : @YES,	// FDs (backwards by type)
		@"Mode3SortColumn" : @4001, @"Mode3SortDescending" : @NO,	// Modules (by address)
	}];
	configChange = @"";
	configId = 0;
	selectedPid = -1;
	fullScreen = NO;
	// 后台无头拉起不会走 viewWillAppear -> reappearAllView，columns 会一直是 nil，
	// 但 UIKit 仍会 layout tableView 并问 cellForRowAtIndexPath（崩溃栈正是
	// CA::Transaction -> UITableView layoutSubviews -> cellForRowAtIndexPath）。
	// 在 viewDidLoad 就初始化一次；viewWillAppear 时再按实际窗口宽度刷新一次。
	[self columnConfigChanged];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)filterText
{
	[procs filter:filterText column:filterColumn];
	[self.tableView reloadData];
	[footer updateSummaryWithColumns:columns procs:procs];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
	searchBar.placeholder = [NSString stringWithFormat:@"filter by %@ <tap another column>", filterColumn.fullname.lowercaseString];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
	searchBar.placeholder = [NSString stringWithFormat:@"filter by %@", filterColumn.fullname.lowercaseString];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
	[searchBar resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
	[filter resignFirstResponder];
}

// 系统 UIBarButtonSystemItemPause / Play 是实心一大坨。
// 这里自绘描边图标：外轮廓用系统原版蓝色、中间镂空（不填充），尺寸比上一版放大一档。
// AlwaysTemplate 交给 UIBarButtonItem 的 tintColor 染色，颜色与系统按钮完全一致。
static UIImage *CTRefreshToggleImage(BOOL play)
{
	const CGFloat k = 26.0;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(k, k), NO, 0);
	[[UIColor blackColor] setStroke];	// template 只取 alpha，颜色由 tintColor 决定

	UIBezierPath *path = [UIBezierPath bezierPath];
	if (play) {
		[path moveToPoint:CGPointMake(9, 4.5)];
		[path addLineToPoint:CGPointMake(20, 13)];
		[path addLineToPoint:CGPointMake(9, 21.5)];
		[path closePath];
	} else {
		[path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(7, 4.5, 4.5, 17) cornerRadius:1.5]];
		[path appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(14.5, 4.5, 4.5, 17) cornerRadius:1.5]];
	}
	path.lineWidth = 1.8;
	path.lineJoinStyle = kCGLineJoinRound;
	[path stroke];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// 右上按钮：暂停/恢复每秒自动刷新。暂停只在当前页面有效，离开再返回自动恢复。
- (UIBarButtonItem *)refreshToggleItem
{
	static UIImage *pauseIcon = nil;
	static UIImage *playIcon = nil;
	if (!pauseIcon) {
		pauseIcon = CTRefreshToggleImage(NO);
		playIcon = CTRefreshToggleImage(YES);
	}
	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:(refreshPaused ? playIcon : pauseIcon)
		style:UIBarButtonItemStylePlain target:self action:@selector(toggleRefreshPaused)];
	// 原版蓝色（自适应深浅色），不用灰色
	if (@available(iOS 13, *))
		item.tintColor = UIColor.systemBlueColor;
	else
		item.tintColor = [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
	return item;
}

- (void)toggleRefreshPaused
{
	refreshPaused = !refreshPaused;
	self.navigationItem.rightBarButtonItem = [self refreshToggleItem];
	if (refreshPaused) {
		if (timer.isValid)
			[timer invalidate];
		timer = nil;
	} else {
		// 恢复时立刻刷新一帧，并重新接上定时器链
		[self refreshProcs:nil];
	}
}

// 统一的定时器续期：暂停时不排下一次；间隔异常时也不排 0 秒定时器
- (void)rearmRefreshTimer
{
	if (refreshPaused || timerInterval < 0.1)
		return;
	if (timer.isValid)
		[timer invalidate];
	if (timerInterval >= 0.1 + NTSTAT_PREQUERY_INTERVAL)
		timer = [NSTimer scheduledTimerWithTimeInterval:(timerInterval - NTSTAT_PREQUERY_INTERVAL)
			target:self selector:@selector(preRefreshProcs:) userInfo:nil repeats:NO];
	else
		timer = [NSTimer scheduledTimerWithTimeInterval:timerInterval
			target:self selector:@selector(refreshProcs:) userInfo:nil repeats:NO];
}

- (void)preRefreshProcs:(NSTimer *)_timer
{
	if (refreshPaused)
		return;
	// Time to query network statistics（拖动/惯性滚动期间跳过，避免额外占用主线程）
	if (!self.tableView.isTracking && !self.tableView.isDecelerating)
		[procs.nstats query];
	// And update the view when statistics arrive
	if (timer.isValid)
		[timer invalidate];
	timer = [NSTimer scheduledTimerWithTimeInterval:NTSTAT_PREQUERY_INTERVAL target:self selector:@selector(refreshProcs:) userInfo:nil repeats:NO];
}

- (void)refreshProcs:(NSTimer *)_timer
{
	// 先续上定时器链，保证跳过某一帧不会让自动刷新永久停摆
	[self rearmRefreshTimer];
	// 暂停中 / 手指拖动 / 惯性滚动 / 正在 kill 进程：跳过本次采集与全表 reloadData
	if (refreshPaused || self.tableView.isTracking || self.tableView.isDecelerating || self.tableView.editing)
		return;
	NSUInteger rowsBefore = [self.tableView numberOfRowsInSection:0];
	[procs refresh];
	[procs sortUsingComparator:sortColumn.sort desc:sortDescending];
	[procs filter:filter.text column:filterColumn];
	if (rowsBefore != procs.count) {
		// 进程增删导致行数变化，必须让 tableView 重建
		[self.tableView reloadData];
	} else {
		// 行数不变：只刷新可见 cell 的文本与底色，避免每秒一次全表 reloadData
		// （reloadData 会重算全部行高、重问 dataSource、重绘 header/footer）
		for (UITableViewCell *cell in self.tableView.visibleCells) {
			NSIndexPath *ip = [self.tableView indexPathForCell:cell];
			if (!ip || (NSUInteger)ip.row >= procs.count || ![cell isKindOfClass:[GridTableCell class]])
				continue;
			PSProc *p = procs[ip.row];
			[(GridTableCell *)cell updateWithProc:p columns:columns];
			cell.backgroundColor = CTCellBackgroundColor(
				p.display == ProcDisplayTerminated,
				p.display == ProcDisplayStarted,
				(ip.row & 1) != 0);
		}
	}
	[footer updateSummaryWithColumns:columns procs:procs];
	// Status bar
// Also add: Uptime, CPU Freq, Cores, Cache L1/L2
//    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
//		statusLabel.text = [NSString stringWithFormat:@"Free: %.1f MB  CPU: %.1f%%",
//			(float)procs.memFree / 1024 / 1024,
//			(float)procs.totalCpu / 10];
//    } else {
//		statusLabel.text = [NSString stringWithFormat:@"Processes: %lu   Threads: %lu   Free: %.1f/%.1f MB   CPU: %.1f%%",
//			(unsigned long)procs.totalCount,
//			(unsigned long)procs.threadCount,
//			(float)procs.memFree / 1024 / 1024,
//			(float)procs.memTotal / 1024 / 1024,
//			(float)procs.totalCpu / 10];
//    }
    bool shortLabel;
    if (@available(iOS 8, *)) {
        UIUserInterfaceSizeClass sizeClass;
        if (self.view.window == nil) {
            sizeClass = [UIApplication sharedApplication].keyWindow.traitCollection.horizontalSizeClass;
        } else {
            sizeClass = self.view.window.traitCollection.horizontalSizeClass;
        }
        shortLabel = (sizeClass == UIUserInterfaceSizeClassCompact);
    } else {
        shortLabel = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone;
    }
    
    // 宽度没变就不重设 frame（每秒刷新时避免无谓的 layout 触发）
    CGFloat labelWidth = self.tableView.frame.size.width - (shortLabel ? 80 : 150);
    if (statusLabel.frame.size.width != labelWidth)
        statusLabel.frame = CGRectMake(statusLabel.frame.origin.x, statusLabel.frame.origin.y, labelWidth, 40);
    statusLabel.text = shortLabel
        ? [NSString stringWithFormat:@"Free: %.1f MB  CPU: %.1f%%",
            (float)procs.memFree / 1024 / 1024, (float)procs.totalCpu / 10]
        : [NSString stringWithFormat:@"Processes: %lu   Threads: %lu   Free: %.1f/%.1f MB   CPU: %.1f%%",
            (unsigned long)procs.totalCount, (unsigned long)procs.threadCount,
            (float)procs.memFree / 1024 / 1024, (float)procs.memTotal / 1024 / 1024,
            (float)procs.totalCpu / 10];
	// Query network statistics, cause no one did it before.
	if (![_timer isKindOfClass:[NSTimer class]])
		[procs.nstats query];
	// First time refresh? Or returned from a sub-page.
	if (_timer == nil) {
		// We don't need info about new processes, they are all new :)
		[procs setAllDisplayed:ProcDisplayNormal];
		NSUInteger idx = NSNotFound;
		if (selectedPid != -1) {
			idx = [procs indexForPid:selectedPid];
			selectedPid = -1;
		}
		if (idx != NSNotFound && procs[idx].display != ProcDisplayTerminated) {
			[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
//#if __IPHONE_OS_VERSION_MAX_ALLOWED < __IPHONE_7_0
            if (@available(iOS 7, *)) {
                
            } else {
                [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0] animated:YES];
            }
//#endif
		}
	} else if ([[[CocoaTopPreferences sharedPreferences] objectForKey:@"AutoJumpNewProcess"] boolValue]) {
		// If there's a new/terminated process, scroll to it
		NSUInteger
			idx = [procs indexOfDisplayed:ProcDisplayStarted];
		if (idx == NSNotFound)
			idx = [procs indexOfDisplayed:ProcDisplayTerminated];
		if (idx != NSNotFound) {
			// Processes at the end of the list are in priority for scrolling!
			PSProc *last = procs[procs.count-1];
			if (last.display == ProcDisplayStarted || last.display == ProcDisplayTerminated)
				idx = procs.count-1;
			[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]
				atScrollPosition:UITableViewScrollPositionNone animated:YES];
		}
		// [self.tableView insertRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:UITableViewRowAnimationAutomatic]
		// [self.tableView deleteRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:UITableViewRowAnimationAutomatic]
	}
}

- (void)sortHeader:(UIGestureRecognizer *)gestureRecognizer
{
	CGPoint loc = [gestureRecognizer locationInView:header];
	for (PSColumn *col in columns) {
		if (loc.x > col.width) {
			loc.x -= col.width;
			continue;
		}
		if (filter.isFirstResponder && !filter.text.length) {
			// Change filtering column
			filterColumn = col;
			[[CocoaTopPreferences sharedPreferences] setObject:@(col.tag) forKey:@"FilterColumn"];
			[self searchBarTextDidEndEditing:filter];
		} else {
			// Change sorting column
			sortDescending = sortColumn == col ? !sortDescending : col.style & ColumnStyleSortDesc;
			[header sortColumnOld:sortColumn New:col desc:sortDescending];
			sortColumn = col;
			[[CocoaTopPreferences sharedPreferences] setObject:@(col.tag) forKey:@"SortColumn"];
			[[CocoaTopPreferences sharedPreferences] setObject:@(sortDescending) forKey:@"SortDescending"];
			[timer fire];
		}
		break;
	}
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
	if (gestureRecognizer.state != UIGestureRecognizerStateBegan) return;
	CGPoint pt = [gestureRecognizer locationInView:self.tableView];
	NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:pt];
	if (!indexPath) return;
	PSProc *p = procs[indexPath.row];
	if (!p || !p.executable || p.executable.length == 0) {
		[[[UIAlertView alloc] initWithTitle:@"提示" message:@"无可用路径" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil] show];
		return;
	}
	UIPasteboard *pb = [UIPasteboard generalPasteboard];
	pb.string =[p.executable lastPathComponent];
	// 已静默复制到剪贴板（不提示）
}

- (void)scrollToBottom
{
	[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:[self.tableView numberOfRowsInSection:0]-1 inSection:0]
		atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (void)columnConfigChanged
{
	// When configId changes, all cells are reconfigured
	configId++;
	// 后台无头启动时 keyWindow 可能为 nil（宽度为 0 -> psGetShownColumnsWithWidth 第一列就 break 返回空数组）。
	// 用 UIScreen 兜底，保证 columns 至少含第一列，避免空列触发下游越界/无符号下溢。
	CGFloat windowWidth = UIApplication.sharedApplication.keyWindow.bounds.size.width;
	if (windowWidth <= 0)
		windowWidth = UIScreen.mainScreen.bounds.size.width;
	columns = [PSColumn psGetShownColumnsWithWidth:windowWidth];
	// Find sort column and create table header
	filterColumn = [PSColumn psColumnWithTag:[[[CocoaTopPreferences sharedPreferences] objectForKey:@"FilterColumn"] integerValue]];
	[self searchBarTextDidEndEditing:filter];
	sortColumn = [PSColumn psColumnWithTag:[[[CocoaTopPreferences sharedPreferences] objectForKey:@"SortColumn"] integerValue]];
	if (!sortColumn) sortColumn = columns.count ? columns[0] : [PSColumn psColumnWithTag:3];
	sortDescending = [[[CocoaTopPreferences sharedPreferences] objectForKey:@"SortDescending"] boolValue];
	header = [GridHeaderView headerWithColumns:columns size:CGSizeMake(self.tableView.bounds.size.width, self.tableView.sectionHeaderHeight)];
	footer = [GridHeaderView footerWithColumns:columns size:CGSizeMake(self.tableView.bounds.size.width, self.tableView.sectionFooterHeight)];
	[header sortColumnOld:nil New:sortColumn desc:sortDescending];
	[header addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sortHeader:)]];
	[footer addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrollToBottom)]];
}

- (void)reappearAllView {
    // When major options change, process list is rebuilt from scratch
	NSString *configCheck = [NSString stringWithFormat:@"%d-%@", [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShortenPaths"] boolValue], [[CocoaTopPreferences sharedPreferences] objectForKey:@"FirstColumnStyle"]];
    if (![configChange isEqualToString:configCheck]) {
        procs = [PSProcArray psProcArrayWithIconSize:self.tableView.rowHeight];
        configChange = configCheck;
    }
    [self columnConfigChanged];
    // Hide filter bar
    CGFloat minOffset = filter.frame.size.height - self.tableView.realUIContentInset.top;
    if (self.tableView.contentOffset.y < minOffset)
        self.tableView.contentOffset = CGPointMake(0, minOffset);
    // Refresh interval
	timerInterval = [[[CocoaTopPreferences sharedPreferences] objectForKey:@"UpdateInterval"] floatValue];
    [self refreshProcs:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.view.window != nil) {
        if (@available(iOS 8, *)) {
            if (lastHorizationWindowSizeClass != self.view.window.traitCollection.horizontalSizeClass || lastHorizationWindowWidth != self.view.bounds.size.width) {
                if (self.view.window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
                    statusLabel.frame = CGRectMake(statusLabel.frame.origin.x, statusLabel.frame.origin.y, self.tableView.frame.size.width - 80, 40);
                    statusLabel.text = [NSString stringWithFormat:@"Free: %.1f MB  CPU: %.1f%%",
                    (float)procs.memFree / 1024 / 1024,
                    (float)procs.totalCpu / 10];
                } else {
                    statusLabel.frame = CGRectMake(statusLabel.frame.origin.x, statusLabel.frame.origin.y, self.tableView.frame.size.width - 150, 40);
                    statusLabel.text = [NSString stringWithFormat:@"Processes: %lu   Threads: %lu   Free: %.1f/%.1f MB   CPU: %.1f%%",
                    (unsigned long)procs.totalCount,
                    (unsigned long)procs.threadCount,
                    (float)procs.memFree / 1024 / 1024,
                    (float)procs.memTotal / 1024 / 1024,
                    (float)procs.totalCpu / 10];
                }
                lastHorizationWindowSizeClass = self.view.window.traitCollection.horizontalSizeClass;
                lastHorizationWindowWidth = self.view.bounds.size.width;
                [self reappearAllView];
            }
        }
    }
}


- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	// 暂停只在当前页面停留期间有效：点进进程详情 / Summary / Modules / Threads 再返回，
	// 自动恢复每秒刷新，不持久化暂停状态。下面的 reappearAllView 会刷一帧并接上定时器链。
	if (refreshPaused) {
		refreshPaused = NO;
		timer = nil;
	}
	self.navigationItem.rightBarButtonItem = [self refreshToggleItem];
    if (@available(iOS 7, *)) {
        self.navigationController.navigationBar.barTintColor = nil;
    } else {
        self.navigationController.navigationBar.tintColor = nil;
    }
    [self reappearAllView];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	if (timer.isValid)
		[timer invalidate];
	header = nil;
	footer = nil;
	columns = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
	if ((fromInterfaceOrientation == UIInterfaceOrientationPortrait || fromInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) &&
		(self.interfaceOrientation == UIInterfaceOrientationPortrait || self.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown))
		return;
	if ((fromInterfaceOrientation == UIInterfaceOrientationLandscapeLeft || fromInterfaceOrientation == UIInterfaceOrientationLandscapeRight) &&
		(self.interfaceOrientation == UIInterfaceOrientationLandscapeLeft || self.interfaceOrientation == UIInterfaceOrientationLandscapeRight))
		return;
	[self columnConfigChanged];
	[timer fire];
}

#pragma mark -
#pragma mark Table view data source

// Section header/footer will be used as a grid header/footer
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{ return [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShowHeader"] boolValue] && !fullScreen ? header : nil; }

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{ return [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShowFooter"] boolValue] && !fullScreen ? footer : nil; }

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{ return [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShowHeader"] boolValue] && !fullScreen ? self.tableView.sectionHeaderHeight : 0; }

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{ return [[[CocoaTopPreferences sharedPreferences] objectForKey:@"ShowFooter"] boolValue] && !fullScreen ? self.tableView.sectionFooterHeight : 0; }

// Customize the number of sections in the table view.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

// Data is acquired from PSProcArray
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return procs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	PSProc *proc = nil;
	if (indexPath.row < procs.count && columns && columns.count)
		proc = procs[indexPath.row];
	GridTableCell *cell = [tableView dequeueReusableCellWithIdentifier:[GridTableCell reuseIdWithIcon:proc.icon != nil]];
	if (cell == nil)
		cell = [GridTableCell cellWithIcon:proc.icon != nil];
	[cell configureWithId:configId columns:columns size:CGSizeMake(0, tableView.rowHeight)];
	// 白色版样式：白底行(偶数行)显示短小竖线，浅灰斑马纹行(奇数行)不显示
	[cell setVerticalDividersVisible:!(indexPath.row & 1)];
	if (proc)
		[cell updateWithProc:proc columns:columns];
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	display_t display = ((PSProc *)procs[indexPath.row]).display;
	cell.backgroundColor = CTCellBackgroundColor(
		display == ProcDisplayTerminated,
		display == ProcDisplayStarted,
		(indexPath.row & 1) != 0);
}

- (void)tableView:(UITableView *)tableView sendSignal:(int)sig toProcessAtIndexPath:(NSIndexPath *)indexPath
{
	PSProc *proc = procs[indexPath.row];
	// task_for_pid(mach_task_self(), pid, &task)
	// task_terminate(task)
	if (kill(proc.pid, sig)) {
		NSString *msg = [NSString stringWithFormat:@"Error %d while terminating app", errno];
		[[[UIAlertView alloc] initWithTitle:proc.name message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
	}
	// Refresh immediately to show process termination
	tableView.editing = NO;
	[timer performSelector:@selector(fire) withObject:nil afterDelay:.1f];
}

- (NSMutableDictionary *)getBlacklistAppConfig
{
	NSMutableDictionary *rootHideConfig = [NSMutableDictionary dictionaryWithContentsOfFile:ROOT_HIDE_CONFIG_PLIST];
	if (!rootHideConfig){
		NSLog(@"[----] rootHideConfig is nil, create new one");
		rootHideConfig = [NSMutableDictionary dictionary];
	}
		
	NSMutableDictionary *appconfig = [rootHideConfig[@"appconfig"] mutableCopy];
	if (!appconfig) {
		NSLog(@"[----] appconfig is nil, create new one");
		appconfig = [NSMutableDictionary dictionary];
	}
	return appconfig;
}

- (NSString *)bundleIdentifierForProcess:(PSProc *)proc
{
	if (![proc.app isKindOfClass:[NSDictionary class]])
		return nil;
	NSString *bundleIdentifier = proc.app[@"CFBundleIdentifier"];
	return [bundleIdentifier isKindOfClass:[NSString class]] && bundleIdentifier.length ? bundleIdentifier : nil;
}

- (BOOL)isBlackListedForProcess:(PSProc *)proc
{
	NSString *bundleIdentifier = [self bundleIdentifierForProcess:proc];
	if (!bundleIdentifier.length)
		return NO;
		
	NSMutableDictionary *appconfig = [self getBlacklistAppConfig];
	return [appconfig[bundleIdentifier] boolValue];
}

- (BOOL)setBlacklisted:(BOOL)blacklisted forProcess:(PSProc *)proc
{
	NSString *bundleIdentifier = [self bundleIdentifierForProcess:proc];
	if (!bundleIdentifier.length) {
		NSLog(@"[----] bundleIdentifier is nil for proc: %@", proc.name);
		return NO;
	}
	NSMutableDictionary *rootHideConfig = [NSMutableDictionary dictionaryWithContentsOfFile:ROOT_HIDE_CONFIG_PLIST];
	if (!rootHideConfig){
		NSLog(@"[----] rootHideConfig is nil, create new one");
		rootHideConfig = [NSMutableDictionary dictionary];
	}
		
	NSMutableDictionary *appconfig = [rootHideConfig[@"appconfig"] mutableCopy];
	if (!appconfig) {
		NSLog(@"[----] appconfig is nil, create new one");
		appconfig = [NSMutableDictionary dictionary];
	}
	appconfig[bundleIdentifier] = @(blacklisted);
	rootHideConfig[@"appconfig"] = appconfig;
	return [rootHideConfig writeToFile:ROOT_HIDE_CONFIG_PLIST atomically:YES];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return @"KILL";
}

- (NSString *)tableView:(UITableView *)tableView titleForSwipeAccessoryButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// 开启/禁止注入开关写入 RootHideConfig 后根本不生效，已整体移除；左滑只保留 KILL
	return nil;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete)
		[self tableView:tableView sendSignal:SIGKILL toProcessAtIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView swipeAccessoryButtonPushedForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// 注入开关已移除，保留空实现兼容系统调用
}

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	BOOL anim = NO;
//#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_7_0
	// Shitty bug in iOS 7
    if (@available(iOS 7, *)) {
        if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_8_0) {
            anim = YES;
        }
        anim = true;
    }
//#endif
	if (filter.isFirstResponder)
		[filter resignFirstResponder];
	// Return from fullscreen, or there's no way back ;)
	if (fullScreen)
		[self hideShowNavBar:nil];
	PSProc *proc = procs[indexPath.row];
	selectedPid = proc.pid;
	[self.navigationController pushViewController:[[SockViewController alloc] initWithProc:proc] animated:anim];
}

#pragma mark -
#pragma mark Memory management

- (void)viewDidUnload
{
	if (timer.isValid)
		[timer invalidate];
	statusLabel = nil;
	header = nil;
	footer = nil;
	sortColumn = nil;
	filterColumn = nil;
	procs = nil;
	columns = nil;
	[super viewDidUnload];
}

- (void)dealloc
{
	if (timer.isValid)
		[timer invalidate];
}

@end
