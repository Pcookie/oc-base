##CFRunLoop 
请对照文件夹中CFRunloop.c看

###(一)weakup&sleep

__CFRunLoopRun 使用mach_absolute_time这个函数拿了循环时间戳 初始化端口队列之类的事情  执行了CFRunLoopTimeout函数 内部调用 CFRunLoopWakeUp 内部调用

	㈠ ret = __CFSendTrivialMachMessage(rl->_wakeUpPort, 0, MACH_SEND_TIMEOUT, 0);
	
当上面这句代码执行后 ㈣ 将收到消息继续执行。闭环

看__CFSendTrivialMachMessage内部 调用

	㈡ result = mach_msg(&header, MACH_SEND_MSG|options, header.msgh_size, 0, MACH_PORT_NULL, timeout, MACH_PORT_NULL);
	
从上个函数传过来的是wakeupport 所以这句话发送了一个消息给 rl->_ wakeUpPort唤醒了runloop

####而_wakeUpPort是如何工作的

runloop创建的代码__CFRunLoopCreate 其中有一句 

	㈢ loop->_wakeUpPort = CFPortAllocate();

实现了wakeUpPort的创建

####当wakeUpPort收到消息后由谁来处理

在__CFRunLoopServiceMachPort内部有这样一句

	㈣ ret = mach_msg(msg, MACH_RCV_MSG|MACH_RCV_LARGE|((TIMEOUT_INFINITY != timeout) ? MACH_RCV_TIMEOUT :0)|MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0)|MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AV),0, msg->msgh_size, port, timeout, MACH_PORT_NULL);

__CFRunLoopServiceMachPort执行会停留在这句上等待消息，而当最前面的哪行代码 ㈠ 当这行代码执行后 ㈣ 将收到消息继续执行 形成了闭环

总结:
sleep本质上来说就是通过调用mach_msg使runloop进入等待消息的状态。
wakeup本质上来说就是通过发送一套消息给mach_msg监听的端口打破mach_msg等待的状态继续向下执行。

###(二) mode

__CFRunLoop及业务逻辑

	struct __CFRunLoop {
	    CFRuntimeBase _base; // 定义一个最基本的对象 一个cfisa 一个uint8_t _cfinfo[4];
	    pthread_mutex_t _lock;	// 锁定的存取mode的列表		/* locked for accessing mode list */
	    __CFPort _wakeUpPort;	// 唤醒端口，被CFRunLoopWakeUp使用 		// used for CFRunLoopWakeUp
	    Boolean _unused; // 未用过的
	    volatile _per_run_data *_perRunData;    // 重置循环           // reset for runs of the run loop
	    pthread_t _pthread; // 线程
	    uint32_t _winthread; // 封装了对线程的操作 ?? 可是他是int类型
	    CFMutableSetRef _commonModes; // set数据结构 放了mode 是整个runloop所包含的mode的集合，请注意这里的_commonModes并不是等价于kCFRunLoopCommonModes。
	    CFMutableSetRef _commonModeItems; // set数据结构  放了modeItem?
	    CFRunLoopModeRef _currentMode; // 当前循环mode
	    CFMutableSetRef _modes;
	    struct _block_item *_blocks_head; // 头
	    struct _block_item *_blocks_tail; // 尾
	    CFAbsoluteTime _runTime; // 运行时间
	    CFAbsoluteTime _sleepTime; // 睡眠时间
	    CFTypeRef _counterpart; //
	};
	
	
	struct __CFRunLoopMode {
	    CFRuntimeBase _base;
	    pthread_mutex_t _lock; /* must have the run loop locked before locking this */
	    CFStringRef _name;
	    Boolean _stopped;
	    char _padding[3];
	    
	    CFMutableSetRef _sources0;
	    CFMutableSetRef _sources1;
	    CFMutableArrayRef _observers;
	    CFMutableArrayRef _timers;
	    // 分别对应着runloop中常常提到的三种source、observer、timer也就是数组，存放了这三种结构。
	    // 通过CFRunLoopAddSource、CFRunLoopAddObserver、CFRunLoopAddTimer分别添加。（看下面）分析
	    
	    CFMutableDictionaryRef _portToV1SourceMap;
	    __CFPortSet _portSet;
	    CFIndex _observerMask;
	#if USE_DISPATCH_SOURCE_FOR_TIMERS
	    dispatch_source_t _timerSource;
	    dispatch_queue_t _queue;
	    Boolean _timerFired; // set to true by the source when a timer has fired
	    Boolean _dispatchTimerArmed;
	#endif
	#if USE_MK_TIMER_TOO
	    mach_port_t _timerPort;
	    Boolean _mkTimerArmed;
	#endif
	#if DEPLOYMENT_TARGET_WINDOWS
	    DWORD _msgQMask;
	    void (*_msgPump)(void);
	#endif
	    uint64_t _timerSoftDeadline; /* TSR */
	    uint64_t _timerHardDeadline; /* TSR */
	};
CFRunLoopAddSource代码如下
简单来说就是如果一个source注册到了kCFRunLoopCommonModes就相当于注册到了所有在_commonModes数组里的mode之中，_commonModes里默认有两种mode：：kCFRunLoopDefaultMode 和 UITrackingRunLoopMode。UITrackingRunLoopMode是scrollview滑动时所在的mode，因此如果在滑动scrollview需要保证图片下载，音频播放等source的性能，将这些source注册为kCFRunLoopCommonModes即可。

	void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef rls, CFStringRef modeName) { /* DOES CALLOUT */
    	CHECK_FOR_FORK();
    	if (__CFRunLoopIsDeallocating(rl)) return;
    	if (!__CFIsValid(rls)) return;
    	Boolean doVer0Callout = false;
    	__CFRunLoopLock(rl);
		//当添加的source注册到了commonmodes的时候
	   if (modeName == kCFRunLoopCommonModes) {
			CFSetRef set = rl->_commonModes ? CFSetCreateCopy(kCFAllocatorSystemDefault, rl->_commonModes) : NULL;
			if (NULL == rl->_commonModeItems) {
				//将source增加到_commonModeItems中
	    		rl->_commonModeItems = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
			}
			CFSetAddValue(rl->_commonModeItems, rls);
			if (NULL != set) {
	    		CFTypeRef context[2] = {rl, rls};
	    		/* add new item to all common-modes */
				//将新增的source同步到_commonModes的所有mode中
	    		CFSetApplyFunction(set, (__CFRunLoopAddItemToCommonModes), (void *)context);
	    		CFRelease(set);
			}
	   } else {
			......
		}
	}
个人观点:注册到kCFRunLoopCommonModes 其实就是 共享了_commonModes里面所有mode的特性 而 _commonModes 里面默认存在kCFRunLoopDefaultMode和UITrackingRunLoopMode两种mode

source定义

	struct __CFRunLoopSource {
	    CFRuntimeBase _base;
	    uint32_t _bits;
	    pthread_mutex_t _lock;
	    CFIndex _order; /* immutable */
	    CFMutableBagRef _runLoops;
	    union {
	        CFRunLoopSourceContext version0; /* immutable, except invalidation */
	        CFRunLoopSourceContext1 version1; /* immutable, except invalidation */
	    } _context;
	};

CFRunLoopSourceContext定义

	typedef struct {
	    CFIndex version;
	    void * info;
	    const void *(*retain)(const void *info);
	    void (*release)(const void *info);
	    CFStringRef (*copyDescription)(const void *info);
	    Boolean (*equal)(const void *info1, const void *info2);
	    CFHashCode (*hash)(const void *info);
	    void (*schedule)(void *info, CFRunLoopRef rl, CFStringRef mode);
	    void (*cancel)(void *info, CFRunLoopRef rl, CFStringRef mode);
	    void (*perform)(void *info); // 这个就是source回调方法的地址
	} CFRunLoopSourceContext;
	
runloop对source调用的过程如下

	/* rl, rlm are locked on entrance and exit */
	static int32_t __CFRunLoopRun(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFTimeInterval seconds, Boolean stopAfterHandle, CFRunLoopModeRef previousMode) {
	......

        Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
        if (sourceHandledThisLoop) {
            __CFRunLoopDoBlocks(rl, rlm);
        }
	......

         CFRUNLOOP_WAKEUP_FOR_SOURCE();
         // Despite the name, this works for windows handles as well
         CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
         if (rls) {
              mach_msg_header_t *reply = NULL;                
              sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) ||  sourceHandledThisLoop;          
	......
	}


	static Boolean __CFRunLoopDoSources0(CFRunLoopRef rl, CFRunLoopModeRef rlm, Boolean stopAfterHandle) { /* DOES CALLOUT */
	......
       __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__(rls->_context.version0.perform, rls->_context.version0.info);
	......
	}


	static void __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__(void (*perform)(void *), void *info) {
	    if (perform) {
	        perform(info);
	    }
	    getpid(); // thwart tail-call optimization
	}
CFRunLoopAddObserver代码如下
	
	void CFRunLoopAddObserver(CFRunLoopRef rl, CFRunLoopObserverRef rlo, CFStringRef modeName) {
    	CHECK_FOR_FORK();
    	CFRunLoopModeRef rlm;
    	if (__CFRunLoopIsDeallocating(rl)) return; // 判断是否正在销毁
    	if (!__CFIsValid(rlo) || (NULL != rlo->_runLoop && rlo->_runLoop != rl)) return; // 判断 rlo 失效  或者 （rlo->rl 存在并且 rlo->rl不等于rl） 两个条件有一个成立 就直接return
    	__CFRunLoopLock(rl); // rl加锁 内部调用pthread_mutex_lock加锁  当pthread_mutex_lock()返回时，该互斥锁已被锁定。线程调用该函数让互斥锁上锁，如果该互斥锁已被另一个线程锁定和拥有，则调用该线程将阻塞，直到该互斥锁变为可用为止
    	if (modeName == kCFRunLoopCommonModes) { 如果观察的是这个字段 就是想看所有mode
			CFSetRef set = rl->_commonModes ? CFSetCreateCopy(kCFAllocatorSystemDefault, rl->_commonModes) : NULL; rl->commonModes 存在就 拷贝一份 给set 如果不存在 就NULL
			
			/****************************************************************************************************/
			/*        KCFALLOCATORDEFAULT	                    默认分配器，与传入NULL等价。                       */
			/****************************************************************************************************/
			/*        kCFAllocatorSystemDefault               原始的默认系统分配器。这个分配器用来应对万一用CFAllocatorSetDefault改变了默认分配器的情况，很少用到。
			/*        kCFAllocatorMalloc	                    调用malloc、realloc和free。如果用malloc创建了内存，那这个分配器对于释放CFData和CFString就很有用。
			/*        kCFAllocatorMallocZone                  在默认的malloc区域中创建和释放内存。在 Mac 上开启了垃圾收集的话，这个分配器会很有用，但在 iOS 中基本上没什么用。
			/*        kCFAllocatorNull                        什么都不做。跟kCFAllocatorMalloc一样，如果不想释放内存，这个分配器对于释放CFData和CFString就很有用。
			/*        KCFAllocatorUseContext                  只有CFAllocatorCreate函数用到。创建CFAllocator时，系统需要分配内存。就像其他所有的Create方法，也需要一个分配器。这个特殊的分配器告诉CFAllocatorCreate用传入的函数来分配CFAllocator。
			/****************************************************************************************************/
			
			if (NULL == rl->_commonModeItems) { 如果items为空
	    		rl->_commonModeItems = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
			}
			CFSetAddValue(rl->_commonModeItems, rlo);
			if (NULL != set) {
			    CFTypeRef context[2] = {rl, rlo};
			    /* add new item to all common-modes */
			    CFSetApplyFunction(set, (__CFRunLoopAddItemToCommonModes), (void *)context);
			    CFRelease(set);
			}
    	} else {
			rlm = __CFRunLoopFindMode(rl, modeName, true);
			if (NULL != rlm && NULL == rlm->_observers) {
	    		rlm->_observers = CFArrayCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeArrayCallBacks);
			}
			if (NULL != rlm && !CFArrayContainsValue(rlm->_observers, CFRangeMake(0, CFArrayGetCount(rlm->_observers)), rlo)) {
           	Boolean inserted = false;
            	for (CFIndex idx = CFArrayGetCount(rlm->_observers); idx--; ) {
                	CFRunLoopObserverRef obs = (CFRunLoopObserverRef)CFArrayGetValueAtIndex(rlm->_observers, idx);
                	if (obs->_order <= rlo->_order) {
                 	CFArrayInsertValueAtIndex(rlm->_observers, idx + 1, rlo);
                    inserted = true;
                    break;
                }
            	}
            	if (!inserted) {
	        		CFArrayInsertValueAtIndex(rlm->_observers, 0, rlo);
            	}
	    		rlm->_observerMask |= rlo->_activities;
	    		__CFRunLoopObserverSchedule(rlo, rl, rlm);
			}
        	if (NULL != rlm) {
	    	__CFRunLoopModeUnlock(rlm);
			}
    	}
    	__CFRunLoopUnlock(rl);
	}
	
###参考文章

* [简书](http://www.jianshu.com/u/2c344e8f8b3d)
* [码迷](http://www.mamicode.com/info-detail-1756855.html)



