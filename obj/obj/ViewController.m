//
//  ViewController.m
//  obj
//
//  Created by pro_cookie on 2017/10/26.
//  Copyright © 2017年 pro_cookie. All rights reserved.
//

#import "ViewController.h"
#import <objc/runtime.h>
#import "TestObject.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
#pragma mark ---
    /**
     
     typedef struct objc_class *Class;
     
     /// Represents an instance of a class.
     struct objc_object {
     Class isa  OBJC_ISA_AVAILABILITY;
     };
     
     */
    //obj为实例变量
#if 0
    id obj = [TestObject new];
    
    Class cls = object_getClass(obj);
    
    Class cls2 = [obj class];
    
    NSLog(@"%p" , cls);
    NSLog(@"%p" , cls2);
#endif
#pragma mark ---
#if 0
    /**
     typedef struct objc_class *Class;
     struct objc_class {
     Class isa;
     Class super_class;
     //followed by runtime specific details...
     };
     */
    //obj为实例变量
    id obj = [TestObject new];
    //classObj为类对象
    Class classObj = [obj class];
    
    Class cls = object_getClass(classObj);
    
    Class cls2 = [classObj class];
    
    NSLog(@"%p" , cls);
    NSLog(@"%p" , cls2);
#endif
#if 0
    //obj为实例变量
    id obj = [TestObject new];
    //classObj为类对象
    Class classObj = [obj class];
    //metaClassObj为元类对象
    Class metaClassObj = object_getClass(classObj);
    
    Class cls = object_getClass(metaClassObj);
    
    Class cls2 = [metaClassObj class];
    
    NSLog(@"%p" , cls);
    NSLog(@"%p" , cls2);
#endif
#if 0
    //obj为实例变量
    id obj = [TestObject new];
    //classObj为类对象
    Class classObj = [obj class];
    //metaClassObj为元类对象
    Class metaClassObj = object_getClass(classObj);
    //rootClassObj为根类对象
    Class rootClassObj = object_getClass(metaClassObj);
    
    Class cls = object_getClass(rootClassObj);
    
    Class cls2 = [rootClassObj class];
    
    NSLog(@"%p" , cls);
    NSLog(@"%p" , cls2);
    
#endif
#if 1
    //obj为实例变量
    id obj = [TestObject new];
    //classObj为类对象
    Class classObj = [obj class];
    //metaClassObj为元类对象
    Class metaClassObj = object_getClass(classObj);
    //rootClassObj为根类对象
    Class rootClassObj = object_getClass(metaClassObj);
    //rootmetaClassObj为根元类对象
    Class rootmetaClassObj = object_getClass(rootClassObj);
    
    Class cls = object_getClass(rootmetaClassObj);
    
    Class cls2 = [rootmetaClassObj class];
    
    NSLog(@"%p" , cls);
    NSLog(@"%p" , cls2);
    
#endif

}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
