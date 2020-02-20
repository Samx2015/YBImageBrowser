//
//  YBImageBrowser.m
//  YBImageBrowserDemo
//
//  Created by 杨波 on 2018/8/24.
//  Copyright © 2018年 杨波. All rights reserved.
//

#import "YBImageBrowser.h"
#import "YBImageBrowserViewLayout.h"
#import "YBImageBrowserView.h"
#import "YBImageBrowser+Internal.h"
#import "YBIBUtilities.h"
#import "YBIBWebImageManager.h"
#import "YBIBTransitionManager.h"
#import "YBIBLayoutDirectionManager.h"
#import "YBIBCopywriter.h"


@interface YBImageBrowser () <UIViewControllerTransitioningDelegate, YBImageBrowserViewDelegate, YBImageBrowserDataSource> {
    BOOL _isFirstViewDidAppear;
    YBImageBrowserLayoutDirection _layoutDirection;
    CGSize _containerSize;
    BOOL _isRestoringDeviceOrientation;
    UIInterfaceOrientation _statusBarOrientationBefore;
    UIWindowLevel _windowLevelByDefault;
}
@property (nonatomic, strong) YBIBLayoutDirectionManager *layoutDirectionManager;
@property (nonatomic, strong) YBIBTransitionManager *transitionManager;
@end

@implementation YBImageBrowser

#pragma mark - life cycle

- (void)dealloc {
    // If the current instance is released (possibly uncontrollable release), we need to restore the changes to external business.
    self.hiddenSourceObject = nil;
    [self setStatusBarHide:NO];
    [self removeObserverForSystem];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.transitioningDelegate = self;
        self.modalPresentationStyle = UIModalPresentationCustom;
        self.automaticallyAdjustsScrollViewInsets = NO;
        
        [self initVars];
        [self.layoutDirectionManager startObserve];
    }
    return self;
}

- (void)initVars {
    _isFirstViewDidAppear = NO;
    _isRestoringDeviceOrientation = NO;
    
    _currentIndex = 0;
    _supportedOrientations = UIInterfaceOrientationMaskAllButUpsideDown;
    _backgroundColor = [UIColor blackColor];
    _enterTransitionType = YBImageBrowserTransitionTypeCoherent;
    _outTransitionType = YBImageBrowserTransitionTypeCoherent;
    _transitionDuration = 0.25;
    _autoHideSourceObject = YES;
    
    if (YBIBLowMemory()) {
        self.shouldPreload = NO;
        self.dataCacheCountLimit = 1;
    } else {
        self.shouldPreload = YES;
        self.dataCacheCountLimit = 8;
    }
    
    YBImageBrowserToolBar *toolBar = [YBImageBrowserToolBar new];
    _defaultToolBar = toolBar;
    _toolBars = @[toolBar];
    
    YBImageBrowserSheetView *sheetView = [YBImageBrowserSheetView new];
    YBImageBrowserSheetAction *saveAction = [YBImageBrowserSheetAction actionWithName:[YBIBCopywriter shareCopywriter].saveToPhotoAlbum identity:kYBImageBrowserSheetActionIdentitySaveToPhotoAlbum action:nil];
    sheetView.actions = @[saveAction];
    _defaultSheetView = sheetView;
    _sheetView = sheetView;
    
    _shouldHideStatusBar = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = _backgroundColor;
    [self addGesture];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    _windowLevelByDefault = self.view.window.windowLevel;
    [self setStatusBarHide:YES];
    
    if (!_isFirstViewDidAppear) {
        
        [self updateLayoutOfSubViewsWithLayoutDirection:[YBIBLayoutDirectionManager getLayoutDirectionByStatusBar]];
        
        [self.browserView scrollToPageWithIndex:_currentIndex];
        
        [self addSubViews];
        
        self->_isFirstViewDidAppear = YES;

        [self addObserverForSystem];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self setStatusBarHide:NO];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.supportedOrientations;
}

- (void)setStatusBarHide:(BOOL)hide {
    if (self.shouldHideStatusBar) {
        self.view.window.windowLevel = hide ? UIWindowLevelStatusBar + 1 : _windowLevelByDefault;
    }
}

#pragma mark - gesture

- (void)addGesture {
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(respondsToLongPress:)];
    [self.view addGestureRecognizer:longPress];
}

- (void)respondsToLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(yb_imageBrowser:respondsToLongPress:)]) {
            [self.delegate yb_imageBrowser:self respondsToLongPress:sender];
            return;
        }
        
        if (self.sheetView && (![[self currentData] respondsToSelector:@selector(yb_browserAllowShowSheetView)] || [[self currentData] yb_browserAllowShowSheetView])) {
            [self.view addSubview:self.sheetView];
            [self.sheetView yb_browserShowSheetViewWithData:[self currentData] layoutDirection:_layoutDirection containerSize:_containerSize];
        }
    }
}

#pragma mark - observe

- (void)removeObserverForSystem {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidChangeStatusBarFrameNotification object:nil];
}

- (void)addObserverForSystem {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeStatusBarFrame) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];
}

- (void)didChangeStatusBarFrame {
    if ([UIApplication sharedApplication].statusBarFrame.size.height > YBIB_HEIGHT_STATUSBAR) {
        self.view.frame = CGRectMake(0, 0, _containerSize.width, _containerSize.height);
    }
}

#pragma mark - private

- (void)addSubViews {
    [self.view addSubview:self.browserView];
    [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.alpha = 0.0f;
        [self.view addSubview:obj];
        if ([obj respondsToSelector:@selector(setYb_browserShowSheetViewBlock:)]) {
            __weak typeof(self) wSelf = self;
            [obj setYb_browserShowSheetViewBlock:^(id<YBImageBrowserCellDataProtocol> _Nonnull data) {
                __strong typeof(wSelf) self = wSelf;
                if (self.sheetView) {
                    [self.view addSubview:self.sheetView];
                    [self.sheetView yb_browserShowSheetViewWithData:data layoutDirection:self->_layoutDirection containerSize:self->_containerSize];
                }
            }];
        }
        // 防止顶部闪烁，添加动画
        [UIView animateWithDuration:0.35f animations:^{
            obj.alpha = 1.0f;
        }];
    }];
}

- (void)updateLayoutOfSubViewsWithLayoutDirection:(YBImageBrowserLayoutDirection)layoutDirection {
    _layoutDirection = layoutDirection;
    CGSize containerSize = layoutDirection == YBImageBrowserLayoutDirectionHorizontal ? CGSizeMake(YBIMAGEBROWSER_HEIGHT, YBIMAGEBROWSER_WIDTH) : CGSizeMake(YBIMAGEBROWSER_WIDTH, YBIMAGEBROWSER_HEIGHT);
    _containerSize = containerSize;
    
    if (self.sheetView && self.sheetView.superview) {
        [self.sheetView yb_browserHideSheetViewWithAnimation:NO];
    }
    
    [self.browserView updateLayoutWithDirection:layoutDirection containerSize:containerSize];
    [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj yb_browserUpdateLayoutWithDirection:layoutDirection containerSize:containerSize];
    }];
}

- (void)pageIndexChanged:(NSUInteger)index {
    _currentIndex = index;
    
    id<YBImageBrowserCellDataProtocol> data = [self currentData];
    
    id sourceObj = nil;
    if ([data respondsToSelector:@selector(yb_browserCellSourceObject)]) {
        sourceObj = data.yb_browserCellSourceObject;
    }
    self.hiddenSourceObject = sourceObj;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(yb_imageBrowser:pageIndexChanged:data:)]) {
        [self.delegate yb_imageBrowser:self pageIndexChanged:index data:data];
    }
    
    [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if (self.defaultToolBar && self.sheetView && [self.sheetView yb_browserActionsCount] >= 2) {
            self.defaultToolBar.operationType = YBImageBrowserToolBarOperationTypeMore;
        }
        
        if ([obj respondsToSelector:@selector(yb_browserPageIndexChanged:totalPage:data:)]) {
            [obj yb_browserPageIndexChanged:index totalPage:[self.dataSource yb_numberOfCellForImageBrowserView:self.browserView] data:data];
        }
    }];
}

#pragma mark - public

- (void)setDataSource:(id<YBImageBrowserDataSource>)dataSource {
    self.browserView.yb_dataSource = dataSource;
}

- (id<YBImageBrowserDataSource>)dataSource {
    return self.browserView.yb_dataSource;
}

- (void)setCurrentIndex:(NSUInteger)currentIndex {
    if (currentIndex + 1 > [self.browserView.yb_dataSource yb_numberOfCellForImageBrowserView:self.browserView]) {
        YBIBLOG_ERROR(@"The index out of range.");
    } else {
        _currentIndex = currentIndex;
        if (self.browserView.superview) {
            [self.browserView scrollToPageWithIndex:currentIndex];
        }
    }
}

- (void)reloadData {
    [self.browserView yb_reloadData];
    [self.browserView scrollToPageWithIndex:_currentIndex];
    [self pageIndexChanged:self.browserView.currentIndex];
}

- (id<YBImageBrowserCellDataProtocol>)currentData {
    return [self.browserView currentData];
}

- (void)show {
    if ([self.browserView.yb_dataSource yb_numberOfCellForImageBrowserView:self.browserView] <= 0) {
        YBIBLOG_ERROR(@"The data sources is invalid.");
        return;
    }
    [self showFromController:YBIBGetTopController()];
}

- (void)showFromController:(UIViewController *)fromController {
    //Preload current data.
    if (self.shouldPreload) {
        id<YBImageBrowserCellDataProtocol> needPreloadData = [self.browserView dataAtIndex:self.currentIndex];
        if ([needPreloadData respondsToSelector:@selector(yb_preload)]) {
            [needPreloadData yb_preload];
        }
        
        if (self.currentIndex == 0) {
            [self.browserView preloadWithCurrentIndex:self.currentIndex];
        }
    }
    
    _statusBarOrientationBefore = [UIApplication sharedApplication].statusBarOrientation;
    self.browserView.statusBarOrientationBefore = _statusBarOrientationBefore;
    [fromController presentViewController:self animated:YES completion:nil];
}

- (void)hide {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setDistanceBetweenPages:(CGFloat)distanceBetweenPages {
    _distanceBetweenPages = distanceBetweenPages;
    ((YBImageBrowserViewLayout *)self.browserView.collectionViewLayout).distanceBetweenPages = distanceBetweenPages;
}

- (BOOL)transitioning {
    return self.transitionManager.transitioning;
}

- (void)setGiProfile:(YBIBGestureInteractionProfile *)giProfile {
    _giProfile = giProfile;
    self.browserView.giProfile = giProfile;
}

- (void)setDataCacheCountLimit:(NSUInteger)dataCacheCountLimit {
    _dataCacheCountLimit = dataCacheCountLimit;
    self.browserView.cacheCountLimit = dataCacheCountLimit;
}

- (void)setShouldPreload:(BOOL)shouldPreload {
    _shouldPreload = shouldPreload;
    self.browserView.shouldPreload = shouldPreload;
}


#pragma mark - internal

- (void)setHiddenSourceObject:(id)hiddenSourceObject {
    if (!_autoHideSourceObject) return;
    if (_hiddenSourceObject && [_hiddenSourceObject respondsToSelector:@selector(setHidden:)]) {
        [_hiddenSourceObject setValue:@(NO) forKey:@"hidden"];
    }
    if (hiddenSourceObject && [hiddenSourceObject respondsToSelector:@selector(setHidden:)]) {
        [hiddenSourceObject setValue:@(YES) forKey:@"hidden"];
    }
    _hiddenSourceObject = hiddenSourceObject;
}

#pragma mark <UIViewControllerTransitioningDelegate>

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    return self.transitionManager;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return self.transitionManager;
}

#pragma mark - <YBImageBrowserViewDelegate>

- (void)yb_imageBrowserViewDismiss:(YBImageBrowserView *)browserView triggerType:(YBImageBrowserDismissTriggerType)triggerType {
    // YBImageBrowserDismissTriggerTypeWithClick 当前事件触发类型是点击触发的才进行处理
    if (([self.fromViewControllerString isEqualToString:@"HDSHomeDetailController"] || [self.fromViewControllerString isEqualToString:@"HDSHomeShareDetailController"]) && triggerType == YBImageBrowserDismissTriggerTypeWithClick) {
        // 如果是从两个详情里进入的图片浏览然后点击了图片
        
        UIInterfaceOrientation interfaceOritation = [[UIApplication sharedApplication] statusBarOrientation];
        [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if (interfaceOritation == UIInterfaceOrientationLandscapeLeft || interfaceOritation == UIInterfaceOrientationLandscapeRight) {
                
                // 如果是横屏状态下，底部的备注栏此时已经隐藏了，需要让底部的备注栏保持原状
                NSString *className = NSStringFromClass([obj class]);
                if (![className isEqualToString:@"HDSImageBrowserBottomBar"]) {
                    obj.hidden = !obj.hidden;
                }
            }else {
                obj.hidden = !obj.hidden;
            }
        }];
    }else {
        // 如果是从其他的页面进入的图片浏览然后点击了图片
        
        [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            obj.hidden = YES;
        }];
        
        if ([UIApplication sharedApplication].statusBarOrientation != self->_statusBarOrientationBefore && [[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
            SEL selector = NSSelectorFromString(@"setOrientation:");
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
            [invocation setSelector:selector];
            [invocation setTarget:[UIDevice currentDevice]];
            NSInteger val = self->_statusBarOrientationBefore;
            [invocation setArgument:&val atIndex:2];
            self->_isRestoringDeviceOrientation = YES;
            [invocation invoke];
        }
        
        [self hide];
    }
}
- (void)yb_imageBrowserViewDismiss:(YBImageBrowserView *)browserView {
    [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.hidden = YES;
    }];
    
    if ([UIApplication sharedApplication].statusBarOrientation != _statusBarOrientationBefore && [[UIDevice currentDevice] respondsToSelector:@selector(setOrientation:)]) {
        SEL selector = NSSelectorFromString(@"setOrientation:");
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[UIDevice instanceMethodSignatureForSelector:selector]];
        [invocation setSelector:selector];
        [invocation setTarget:[UIDevice currentDevice]];
        NSInteger val = _statusBarOrientationBefore;
        [invocation setArgument:&val atIndex:2];
        _isRestoringDeviceOrientation = YES;
        [invocation invoke];
    }
}

- (void)yb_imageBrowserView:(YBImageBrowserView *)browserView changeAlpha:(CGFloat)alpha duration:(NSTimeInterval)duration {
    void (^animationsBlock)(void) = ^{
        self.view.backgroundColor = [self->_backgroundColor colorWithAlphaComponent:alpha];
    };
    void (^completionBlock)(BOOL) = ^(BOOL x){
        if (alpha == 1) [self setStatusBarHide:YES];
        if (alpha < 1) [self setStatusBarHide:NO];
    };
    if (duration <= 0) {
        animationsBlock();
        completionBlock(YES);
    } else {
        [UIView animateWithDuration:duration animations:animationsBlock completion:completionBlock];
    }
}

- (void)yb_imageBrowserView:(YBImageBrowserView *)browserView pageIndexChanged:(NSUInteger)index {
    [self pageIndexChanged:index];
}

- (void)yb_imageBrowserView:(YBImageBrowserView *)browserView hideTooBar:(BOOL)hidden {
    // 19-01-14的改动
    // 只有在视频开始播放/播放结束时才去进行隐藏和显示
    NSArray *array = [NSThread callStackSymbols];
    if (array.count > 2) {
        NSString *methodString = array[2];
        if ([methodString containsString:@"avPlayerItemStatusChanged"]) {
            [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                obj.hidden = YES;
            }];
        }
        if (array.count > 4) {
            NSString *videoFinishString = array[4];
            if ([videoFinishString containsString:@"videoPlayFinish"]) {
                [self.toolBars enumerateObjectsUsingBlock:^(__kindof UIView<YBImageBrowserToolBarProtocol> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    obj.hidden = NO;
                }];
            }
        }
    }
    
    if (self.sheetView && self.sheetView.superview && hidden) {
        [self.sheetView yb_browserHideSheetViewWithAnimation:YES];
    }
}

#pragma mark - <YBImageBrowserDataSource>

- (NSUInteger)yb_numberOfCellForImageBrowserView:(YBImageBrowserView *)imageBrowserView {
    return self.dataSourceArray.count;
}

- (id<YBImageBrowserCellDataProtocol>)yb_imageBrowserView:(YBImageBrowserView *)imageBrowserView dataForCellAtIndex:(NSUInteger)index {
    return self.dataSourceArray[index];
}

#pragma mark - getter

- (YBImageBrowserView *)browserView {
    if (!_browserView) {
        _browserView = [YBImageBrowserView new];
        _browserView.yb_delegate = self;
        _browserView.yb_dataSource = self;
        _browserView.giProfile = [YBIBGestureInteractionProfile new];
    }
    return _browserView;
}

- (YBIBLayoutDirectionManager *)layoutDirectionManager {
    if (!_layoutDirectionManager) {
        _layoutDirectionManager = [YBIBLayoutDirectionManager new];
        __weak typeof(self) wSelf = self;
        [_layoutDirectionManager setLayoutDirectionChangedBlock:^(YBImageBrowserLayoutDirection layoutDirection) {
            __strong typeof(wSelf) self = wSelf;
            if (layoutDirection == YBImageBrowserLayoutDirectionUnknown || self.transitionManager.transitioning || self->_isRestoringDeviceOrientation) return;
            
            [self updateLayoutOfSubViewsWithLayoutDirection:layoutDirection];
        }];
    }
    return _layoutDirectionManager;
}

- (YBIBTransitionManager *)transitionManager {
    if (!_transitionManager) {
        _transitionManager = [YBIBTransitionManager new];
        _transitionManager.imageBrowser = self;
    }
    return _transitionManager;
}

@end
