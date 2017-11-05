INCLUDEDIR=-I`llvm-config --includedir`
LIBDIR=-L`llvm-config --libdir`
SFLAGS=-Xcc $(INCLUDEDIR) -Xlinker -lLLVM -Xlinker $(LIBDIR)

all:
	swift build $(SFLAGS)

release:
	swift build -c release $(SFLAGS)

test:
	swift test $(SFLAGS)

check: all
	lit FileCheck

update:
	swift package update

xcode:
	swift package generate-xcodeproj

clean:
	swift package clean
