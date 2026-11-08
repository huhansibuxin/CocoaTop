#import <UIKit/UIKit.h>
#import "Proc.h"
#import "ProcArray.h"
#import "Sock.h"
#import "Column.h"

// 单元格背景色统一缓存一次：原先每行 willDisplayCell 都会新建一个动态颜色闭包对象
extern UIColor *CTCellBackgroundColor(BOOL terminated, BOOL started, BOOL zebra);

@interface GridTableCell : UITableViewCell
@property (assign) NSUInteger id;
@property (assign) NSUInteger firstColWidth;
@property (assign) BOOL extendArgsLabel;
@property (assign) BOOL colorDiffs;
// 记录当前 cell 是否正在显示图标：图标状态变化时才需要重新 layout 文字缩进
@property (assign) BOOL iconShown;
@property (strong) NSMutableArray *labels;
@property (strong) NSMutableArray *dividers;
+ (NSString *)reuseIdWithIcon:(bool)withicon;
+ (instancetype)cellWithIcon:(bool)withicon;
- (void)configureWithId:(int)id columns:(NSArray *)columns size:(CGSize)size;
// 隔行显示/隐藏列间竖线（白色版样式：隔一行才有一条短小细线）
- (void)setVerticalDividersVisible:(BOOL)visible;
- (void)updateWithProc:(PSProc *)proc columns:(NSArray *)columns;
- (void)updateWithSock:(PSSock *)sock columns:(NSArray *)columns;
@end

@interface GridHeaderView : UITableViewHeaderFooterView
@property (strong) NSMutableArray *labels;
@property (strong) NSMutableArray *dividers;
+ (instancetype)headerWithColumns:(NSArray *)columns size:(CGSize)size;
+ (instancetype)footerWithColumns:(NSArray *)columns size:(CGSize)size;
- (void)sortColumnOld:(PSColumn *)oldCol New:(PSColumn *)newCol desc:(BOOL)desc;
- (void)updateSummaryWithColumns:(NSArray *)columns procs:(PSProcArray *)procs;
@end
