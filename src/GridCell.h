#import <UIKit/UIKit.h>
#import "Proc.h"
#import "ProcArray.h"
#import "Sock.h"
#import "Column.h"

@interface GridTableCell : UITableViewCell
@property (assign) NSUInteger id;
@property (assign) NSUInteger firstColWidth;
@property (assign) BOOL extendArgsLabel;
@property (assign) BOOL colorDiffs;
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
