//
//  ADTTests.swift
//  DLVM
//
//  Copyright 2016-2018 The DLVM Team.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import struct DLVM.OrderedSet
@testable import struct DLVM.DoubleLinkedList

class ADTTests : XCTestCase {
    func testOrderedSet() {
        /// Test CoW
        var set = OrderedSet<Int>()
        set.append(1)
        var setCopy = set
        setCopy.append(2)
        XCTAssertTrue(set.contains(1))
        XCTAssertFalse(set.contains(2))
        XCTAssertTrue(setCopy.contains(1))
        XCTAssertTrue(setCopy.contains(2))

        /// Test range replacement
        var set0: OrderedSet<Int> = [1, 2, 3, 4]
        set0[1...3] = [0, 5, 6]
        XCTAssertEqual(set0, [1, 0, 5, 6])

        /// Test reversal
        var set1: OrderedSet<Int> = [1, 2, 3]
        XCTAssertEqual(set1.reversed(), [3, 2, 1])
        set1.reverse()
        XCTAssertEqual(set1.set, Set(set1.array))
        XCTAssertEqual(set1, [3, 2, 1])
        set1[1...].reverse()
        XCTAssertEqual(set1.set, Set(set1.array))
        XCTAssertEqual(set1, [3, 1, 2])

        /// Test swap
        var set2: OrderedSet<Int> = [1, 2, 3, 4, 5]
        set2.swapAt(1, 3)
        XCTAssertEqual(set2, [1, 4, 3, 2, 5])
    }

    func testDoubleLinkedList() {
        var list = DoubleLinkedList<String>()
        XCTAssertTrue(list.isEmpty())
        list.append(value: "test")
        XCTAssertEqual(list.valueAt(0), "test")
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    static var allTests: [(String, (ADTTests) -> () throws -> Void)] {
        return [
            ("testOrderedSet", testOrderedSet)
        ]
    }
}
