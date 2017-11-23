##CFRunLoop 
###(一)weakup&sleep
#####摘自[简书](http://www.jianshu.com/p/9619d3f3722e)
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


