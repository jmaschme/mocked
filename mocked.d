module unitTest.mocked;

version(unittest) {

	import core.sys.posix.sys.mman;
	import core.memory;
	import std.conv;
	import std.demangle;
	import std.stdio;
	import std.traits;
	import std.typecons;
	import std.typetuple;
	import std.variant;

	private:

		struct MethodCall {
			string name;
			Variant argTuple;
			Variant returnValue;
		}

		MethodCall[] calledMethods;

		void compareArguments(string Name, int Arg, T)(T savedArgs, T newArgs) {
			static if (T.length == 0) {
					return;
				} else static if (T.length == 1) {
						assert(savedArgs[0] == newArgs[0], "Argument " ~ to!string(Arg) ~ " is invalid in call to '" ~ demangle(Name) ~ ".'\nExpected '" ~ to!string(savedArgs[0]) ~ "' but got '" ~ to!string(newArgs[0]) ~ "'");
				} else {
						assert(savedArgs[0] == newArgs[0], "Argument " ~ to!string(Arg) ~ " is invalid in call to '" ~ demangle(Name) ~ ".'\nExpected '" ~ to!string(savedArgs[0]) ~ "' but got '" ~ to!string(newArgs[0]) ~ "'");
						compareArguments!(Name, Arg+1)(savedArgs.slice!(1,savedArgs.length), newArgs.slice!(1,newArgs.length));
				}
		}

		auto mockedMethod(string Name, ReturnType, T...)(T args) {
				static if (!is(ReturnType == void)) 
					ReturnType result = ReturnType.init;
				if (playbackMode) {
						assert(calledMethods.length > 0, "Unexpected call to method \"" ~ demangle(Name) ~ "\"");
						assert(calledMethods[0].name == Name, "Method \"" ~ demangle(Name) ~ "\" called when expecting a call to \"" ~ demangle(calledMethods[0].name) ~ "\"");
						if (args.length > 0) {
								Tuple!(T) savedArgs = calledMethods[0].argTuple.get!(Tuple!(T))();
								Tuple!(T) argsAsTuple = args;
								compareArguments!(Name, 0)(savedArgs, argsAsTuple);
						}
						static if (!is(ReturnType == void)) 
							result = calledMethods[0].returnValue.get!ReturnType();
						calledMethods = calledMethods[1 .. $];
				} else {
						MethodCall call;
						call.name = Name;
						static if (!is(ReturnType == void))
							call.returnValue = ReturnType.init;
						static if (args.length > 0) {
								Tuple!(T) argsAsTuple = args;
								Variant value = argsAsTuple;
								call.argTuple = value;
						}
						calledMethods ~= call;
				}
				static if (is(ReturnType == void)) {
						return;
				} else {
						return result;
				}
		}

		version(linux) {
				extern (C) int mprotect(const void*, uint, int);
				extern (C) int getpagesize();
		}

		void* getPageAlignedAddress(void* address, int pagesize) {
				version(linux) {
						void* alignedAddress = cast(void*)((cast(uint)address) & (~(pagesize-1)));
						return alignedAddress;
				}
		}

		version (internalUnittest) {
				unittest {
						assert(getPageAlignedAddress(cast(void*)0xDEADBEEF, 1024) == cast(void*)0xDEADBC00);
						assert(getPageAlignedAddress(cast(void*)0xDEADBEEF, 8) == cast(void*)0xDEADBEE8);
						assert(getPageAlignedAddress(cast(void*)0xDEADBEEF, 2048) == cast(void*)0xDEADB800);
						assert(getPageAlignedAddress(cast(void*)0xDEADBEEF, 4096) == cast(void*)0xDEADB000);
				}
		}

		void removeMemoryProtection(void* address) {
				version(linux) {
						int pagesize = getpagesize();
						void* alignedAddress = getPageAlignedAddress(address, pagesize);
						mprotect(alignedAddress, pagesize, PROT_READ|PROT_WRITE|PROT_EXEC);
				}
		}

		void protectMemory(void* address) {
				version(linux) {
						int pagesize = getpagesize();
						void* alignedAddress = getPageAlignedAddress(address, pagesize);
						mprotect(alignedAddress, pagesize, PROT_READ|PROT_EXEC);
				}
		}

		ulong[void*] patchedFunctions;

		void patchFunction(Function...)(void* address) {
				removeMemoryProtection(address);
				ulong newInstructions = 0x90e1ff;
				newInstructions <<= 32;
				newInstructions |= cast(uint)&mockedMethod!(Function[0].mangleof, ReturnType!(Function), ParameterTypeTuple!(Function));
				newInstructions <<= 8;
				newInstructions |= 0xb9;
				patchedFunctions[address] = *cast(ulong*)address;
				*cast(ulong*)address = newInstructions;
				protectMemory(address);
		}

		void unpatchFunction(void* address) {
				removeMemoryProtection(address);
				*cast(ulong*)address = patchedFunctions[address];
				protectMemory(address);
				patchedFunctions.remove(address);
		}

		version(internalUnittest) {
				bool freeFunctionTest1Called;
				void freeFunctionTest1() {freeFunctionTest1Called = true;}
				double freeFunctionTest2() {return 0.5;}
		}

		version (internalUnittest) {
				unittest {
						patchFunction!(freeFunctionTest1)(&freeFunctionTest1);
						freeFunctionTest1Called = false;
						freeFunctionTest1();
						assert(!freeFunctionTest1Called);
						unpatchFunction(&freeFunctionTest1);
						freeFunctionTest1();
						assert(freeFunctionTest1Called);

						patchFunction!(freeFunctionTest2)(&freeFunctionTest2);
						assert(freeFunctionTest2() == 0.0);
						unpatchFunction(&freeFunctionTest2);
						assert(freeFunctionTest2() == 0.5);
				}
		}

		void patchMethod(T, Method...)(void* address) {
			removeMemoryProtection(address);
			ulong newInstructions = 0x90e1ff;
			newInstructions <<= 32;
			newInstructions |= cast(uint)&mockedMethod!(Method[0].mangleof, ReturnType!(Method), TypeTuple!(ParameterTypeTuple!(Method)), T);
			newInstructions <<= 8;
			newInstructions |= 0xb9;
			patchedFunctions[address] = *cast(ulong*)address;
			*cast(ulong*)address = newInstructions;
			protectMemory(address);
		}

		void unpatchMethod(void* address) {
				unpatchFunction(address);
		}

		version(internalUnittest) {
				bool methodCalled;
				struct S {
						void method() {methodCalled = true;}
						int method2() {return 5;}
				}
		}

		version (internalUnittest) {
			unittest {
				patchMethod!(S, S.method)(cast(void*)&S.method);
				methodCalled = false;
				S s;
				s.method();
				assert(!methodCalled);
				unpatchMethod(&S.method);
				s.method();
				assert(methodCalled);

				patchMethod!(S, S.method2)(cast(void*)&S.method2);
				assert(s.method2() == 0);
				unpatchMethod(&S.method2);
				assert(s.method2() == 5);
			}

				unittest {
						class Foo {
								void method() {methodCalled = true;}
								int method2() {return 1;}
								bool methodCalled;
						}

						Foo foo = new Foo();
						patchMethod!(Foo, Foo.method)(cast(void*)&Foo.method);
						foo.methodCalled = false;
						foo.method();
						assert(!foo.methodCalled);
						unpatchMethod(&Foo.method);
						foo.method();
						assert(foo.methodCalled);

						patchMethod!(Foo, Foo.method2)(cast(void*)&Foo.method2);
						assert(foo.method2() == 0);
						unpatchMethod(&Foo.method2);
						assert(foo.method2() == 1);
				}
		}

		int findMethodInVtbl(T)(T obj, void* functionAddress) {
				int i = 1;
				while (obj.__vptr[i] != functionAddress) ++i;
				return i;
		}

		version (internalUnittest) {
				unittest {
						class Foo {
								void method() {}
								void method2() {}
						}
						Foo foo = new Foo();
						assert(findMethodInVtbl!Foo(foo, &Foo.method) == 6);
						assert(findMethodInVtbl!Foo(foo, &Foo.method2) == 7);
				}
		}

		alias Tuple!(uint, "index", void*, "method", void**, "vptr") PatchedVirtualMethodRecord;
		PatchedVirtualMethodRecord[void*] patchedVirtualMethods;

		void patchVirtualMethod(T, Method...)(T obj) {
				void* functionAddress = cast(void*)(mixin("&T." ~ __traits(identifier, Method[0])));
				int index = findMethodInVtbl(obj, cast(void*)functionAddress);
				void** ptr =  cast(void**)(obj.__vptr);
				removeMemoryProtection(&ptr[index]);
				PatchedVirtualMethodRecord original;
				original.index = index;
				original.method = ptr[index];
				original.vptr = ptr;
				patchedVirtualMethods[cast(void*)functionAddress] = original;
				ptr[index] = &mockedMethod!(Method[0].mangleof, ReturnType!(Method), TypeTuple!(ParameterTypeTuple!(Method), T));
				protectMemory(&(ptr[index]));
		}

		void unpatchVirtualMethodFromAddress(void* address) {
				int index = patchedVirtualMethods[address].index;
				void** ptr = patchedVirtualMethods[address].vptr;
				removeMemoryProtection(&ptr[index]);
				ptr[index] = patchedVirtualMethods[address].method;
				protectMemory(&ptr[index]);
				patchedVirtualMethods.remove(address);
		}

		void unpatchVirtualMethod(T, Method...)() {
				void* functionAddress = cast(void*)(mixin("&T." ~ __traits(identifier, Method)));
				unpatchVirtualMethodFromAddress(functionAddress);
		}

		version (internalUnittest) {
				unittest {
						class Foo {
								void method() {}
								int method2() {return 1;}
						}

						void* GetMockedMethodAddress(T, Method...)() {
								return &mockedMethod!(Method[0].mangleof, ReturnType!(Method[0]), TypeTuple!(ParameterTypeTuple!(Method[0]), T));
						}

						Foo foo = new Foo();
						patchVirtualMethod!(Foo, Foo.method)(foo);
						assert(foo.__vptr[6] != &Foo.method);
						void* address = GetMockedMethodAddress!(Foo, Foo.method)();
						assert(foo.__vptr[6] == address);
						unpatchVirtualMethod!(Foo, Foo.method)();
						assert(foo.__vptr[6] == &Foo.method);

						patchVirtualMethod!(Foo, Foo.method2)(foo);
						assert(foo.__vptr[7] != &Foo.method2);
						address = GetMockedMethodAddress!(Foo, Foo.method2)();
						assert(foo.__vptr[7] == address);
						assert(foo.method2() == 0);
						unpatchVirtualMethod!(Foo, Foo.method2)();
						assert(foo.__vptr[7] == &Foo.method2);
						assert(foo.method2() == 1);
				}
		}

		void unpatchAll()
		{
				foreach(i; patchedFunctions.keys) {
						unpatchFunction(cast(void*)i);
				}

				foreach(i; patchedVirtualMethods.keys) {
						unpatchVirtualMethodFromAddress(cast(void*)i);
				}
		}

		version (internalUnittest) {
				unittest {
						class Foo {
								int method() { return 1; }
						}
						Foo foo = new Foo();

						patchFunction!(freeFunctionTest1)(cast(void*)&freeFunctionTest1); 
						patchFunction!(freeFunctionTest2)(cast(void*)&freeFunctionTest2); 
						patchVirtualMethod!(Foo, Foo.method)(foo);
						unpatchAll();
						freeFunctionTest1Called = false;
						freeFunctionTest1();
						assert(freeFunctionTest1Called);
						assert(freeFunctionTest2() == 0.5);
						assert(foo.method() == 1);
						assert(patchedFunctions.length == 0);
						assert(patchedVirtualMethods.length == 0);
				}
		}

		template isNestedFunction(T...) {
				enum isNestedFunction = isSomeFunction!(T[0]) &&
						!isDelegate!(T[0]) &&
						!isFunctionPointer!(T[0]) &&
						is(typeof(__traits(parent, T[0]))) &&
						!__traits(isStaticFunction,T[0]);
		}

		version(internalUnittest) {
				void notNested() {}

				unittest {
						void nestedTest() {
								void nested() {}
								assert(isNestedFunction!(nested));
						}
						assert(!isNestedFunction!(notNested));
						nestedTest();
				}
		}

		template isStructMethod(T...) {
				enum isStructMethod = isSomeFunction!(T[0]) &&
						!isDelegate!(T[0]) &&
						!isFunctionPointer!(T[0]) &&
						!__traits(isStaticFunction, T[0]) &&
						!__traits(isVirtualMethod, T[0]) &&
						!isNestedFunction!(T[0]);
		}

		version (internalUnittest) {
				unittest {
						struct Struct {
								void method() {}
								static void staticMethod() {}
						}
						class Class {
								void virtualMethod() {}
								final finalMethod() {}
								static void staticMethod() {}
						}

						void nestedTest() {
								void nested() {}
								assert(!isStructMethod!(nested));
						}

						assert(!isStructMethod!(notNested));
						assert(isStructMethod!(Struct.method));
						assert(!isStructMethod!(Struct.staticMethod));
						assert(!isStructMethod!(Class.virtualMethod));
						assert(isStructMethod!(Class.finalMethod));
						assert(!isStructMethod!(Class.staticMethod));
						nestedTest();
				}
		}

		T allocateClassWithoutConstructing(T)() {
				void[] array;
				size_t* ptr = cast(size_t*)&array;
				enum classSize = __traits(classInstanceSize, T);
				*ptr = cast(size_t)classSize;
				ptr++;
				*ptr = cast(size_t)GC.malloc(12);
				auto result = cast(T)array.ptr;
				(cast(byte[])array)[0 .. classSize] = typeid(T).init[];
				return result;
		}

		version (internalUnittest) {
				unittest {
						class Foo {
								this() {
										val = 5;
								}
								int getVal() {
										return val;
								}
								int val;
						}

						Foo f = allocateClassWithoutConstructing!Foo();
						assert(f.getVal() == 0);
				}
		}

		bool playbackMode = false;

		public:

		struct MockInit {
				~this() {
						unpatchAll();
						assert(calledMethods.length == 0, "Expected calls to method(s) " ~ to!string(calledMethods));
				}
		}

		@property MockInit mockInit() {
				playbackMode = false;
				calledMethods.length = 0;
				return MockInit();
		}

		/* Note that this mixin could simplify initialization, but currently yields an internal compiler error
		   mixin template MockInit() {
		   auto mockInitStructure = mockInit;
		   }*/

		auto mock(T...)() {
				static assert(!__traits(isVirtualMethod, T[0]) && !isStructMethod!(T[0]), "Cannot mock method '" ~ demangle(T[0].mangleof) ~ "' without a class as the first template argument.");
				static if (__traits(isStaticFunction, T)) {
						patchFunction!(T)(&T[0]);
						return;
				} else static if (T.length == 1 && is(T[0] == class)) {
						alias T[0] classType;
						auto obj = allocateClassWithoutConstructing!classType();
						foreach(i; __traits(allMembers, T[0])) {
								static if (__traits(isVirtualMethod, mixin("T[0]." ~ i)) && i != "opEquals") {
										patchVirtualMethod!(T[0], mixin("T[0]." ~i))(obj);
								} else static if ((isStructMethod!(mixin("T[0]." ~ i))) && i != "opEquals") {
										patchMethod!(T[0], mixin("T[0]." ~ i))(cast(void*)&mixin("T[0]." ~ i));
								}
						}
						return obj;
				} else static if (T.length == 1 && is(T[0] == struct)) {
						T[0] obj;
						foreach(i; __traits(allMembers, T[0])) {
								if (isStructMethod!(mixin("T[0]." ~ i)) && i != "opEquals") {
										patchMethod!(T[0], mixin("T[0]." ~ i))(cast(void*)&mixin("T[0]." ~ i));
								}
						}
						return obj;
				} else static if (T.length > 1 && isStructMethod!(T[1]) || __traits(isVirtualMethod, T[1])) {
						patchMethod!(T[0], T[1])(cast(void*)&T[1]);
						return;
				} else static if (isNestedFunction!(T)) {
						assert(0, "Nested Functions are not currently supported");
				} else {
						assert(0, "Do not know how to mock '" ~ demangle(T[0].mangleof) ~ "'");
				}
		}

		void mockVirtual(T...)(T[0] obj) {
				static assert(__traits(isVirtualMethod, T[1]) && is(T[0] == class), "Only virtual class methods require an argument when mocking.");
				patchVirtualMethod!(T[0], mixin("T[0]." ~ __traits(identifier, T[1])))(obj);
		}

		void unmock(T...)()
		{
				static if (__traits(isStaticFunction, T)) {
						unpatchFunction(&T[0]);
				} else static if (isStructMethod!(T[0]) || __traits(isVirtualMethod, T[0])) {
						unpatchMethod(&T[0]);
				} else {
						assert(0);
				}
		}

		void unmockVirtual(T...)(T[0] obj) {
				unpatchVirtualMethod!(T[0], mixin("T[0]." ~ __traits(identifier, T[1])))();
		}

		version (internalUnittest) {
				unittest {
						class Foo {
								void method() {}
								int method2() {return 1;}
						}

						void* GetMockedMethodAddress(T, Method...)() {
								return &mockedMethod!(Method[0].mangleof, ReturnType!(Method[0]), TypeTuple!(ParameterTypeTuple!(Method[0]), T));
						}

						Foo foo = new Foo();
						mockVirtual!(Foo, Foo.method)(foo);
						assert(foo.__vptr[6] != &Foo.method);
						void* address = GetMockedMethodAddress!(Foo, Foo.method)();
						assert(foo.__vptr[6] == address);
						unmockVirtual!(Foo, Foo.method)(foo);
						assert(foo.__vptr[6] == &Foo.method);

						mockVirtual!(Foo, Foo.method2)(foo);
						assert(foo.__vptr[7] != &Foo.method2);
						address = GetMockedMethodAddress!(Foo, Foo.method2)();
						assert(foo.__vptr[7] == address);
						assert(foo.method2() == 0);
						unmockVirtual!(Foo, Foo.method2)(foo);
						assert(foo.__vptr[7] == &Foo.method2);
						assert(foo.method2() == 1);
				}
		}


		void setPlaybackMode(bool enabled = true) {
				playbackMode = enabled;
		}

		auto expect(T)(T returnValue) {
			struct ExpectResult {
				this(int index) {
					this.index = index;
				}
				ExpectResult returnValue(T)(T value) {
					calledMethods[index].returnValue = value;
					return this;
				}
				private int index;
			}
			ExpectResult result = ExpectResult(calledMethods.length-1);
			return result;
		}

		version (internalUnittest) {
			int mockReturn() { return 1; }
			unittest {
				auto m = mockInit;
				mock!(mockReturn)();
			expect(mockReturn()).returnValue(2);
		        setPlaybackMode();
		 assert(mockReturn() == 2);
			}

				void test1() {
				}
				void test2(int x) {
				}
				void methodUnderTest() {
						test1();
						test2(5);
				}

				unittest {
						auto m = mockInit;

						mock!(test1)();
						mock!(test2)();
						test1();
						test2(5);
						setPlaybackMode();
						methodUnderTest(); 
						unmock!(test1)();
						unmock!(test2)();
				}

				class Base {
						public:
								void testMethod1() {}
								void testMethod2(int x) {}
				}
				class TestClass : Base {
						public:
								override void testMethod1() {}
								override void testMethod2(int x) {}
								void methodUnderTest() {
										testMethod1();
										testMethod2(5);
								}
				}

				unittest {
						auto m = mockInit;

						auto obj = new TestClass();

						mock!(TestClass, TestClass.testMethod1)();
						mock!(TestClass, TestClass.testMethod2)();
						obj.testMethod1();
						obj.testMethod2(5);
						setPlaybackMode();
						obj.methodUnderTest();
						unmock!(TestClass.testMethod1)();
						unmock!(TestClass.testMethod2)();
				}

				struct TestStruct {
						void method1() {};
						void method2(int x) {}
						void methodUnderTest() {
								method1();
								method2(5);
						}
				}

				unittest {
						auto m = mockInit;

						TestStruct obj;

						mock!(TestStruct, TestStruct.method1)();
						mock!(TestStruct, TestStruct.method2)();
						obj.method1();
						obj.method2(5);
						setPlaybackMode();
						obj.methodUnderTest();
				}

				struct TestMockFullStruct {
						void method1() {}
						void method2(int x) {}
						bool opEquals(TestMockFullStruct rhs) {
								return true;
						}
				}
				void fullStructFunctionUnderTest(TestMockFullStruct obj) {
						obj.method1();
						obj.method2(5);
				}

				unittest {
						auto m = mockInit;

						TestMockFullStruct obj = mock!(TestMockFullStruct)();
						obj.method1();
						obj.method2(5);
						setPlaybackMode();
						fullStructFunctionUnderTest(obj);
				}

				class TestMockFullClass {
						void method1() {}
						void method2(int x) {}
				}
				void fullClassFunctionUnderTest(TestMockFullClass obj) {
						obj.method1();
						obj.method2(5);
				}

				unittest {
						auto m = mockInit;

						TestMockFullClass obj = mock!(TestMockFullClass)();
						obj.method1();
						obj.method2(5);
						setPlaybackMode();
						fullClassFunctionUnderTest(obj);
				}

				void main() {writeln("All tests passed");}
		}
}
