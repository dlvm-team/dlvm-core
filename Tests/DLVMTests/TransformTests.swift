//
//  TransformTests.swift
//  DLVM
//
//  Created by Richard Wei on 4/27/17.
//
//

import XCTest
@testable import DLVM

class TransformTests: XCTestCase {
    
    let builder = IRBuilder(moduleName: "TransformTest")
    
    /// - TODO: Fix bug in dominance analysis that causes crash
    func testDCE() throws {
        let fun = builder.buildFunction(named: "bar",
                                        argumentTypes: [.scalar(.float(.single)), .scalar(.float(.single))],
                                        returnType: .int(32))
        builder.move(to: builder.buildEntry(argumentNames: ["x", "y"], in: fun))
        let mult = builder.multiply(.literal(.int(32), 5), .literal(.int(32), 8))
        let dead1 = builder.buildInstruction(.numericBinary(.multiply,
                                                            .literal(.int(32), 10000), .literal(.int(32), 20000)),
                                             name: "dead1")
        builder.buildInstruction(.numericBinary(.add, %dead1, 20000 ~ Type.int(32)),
                                 name: "dead2")
        let cmp = builder.compare(.equal, %mult, .literal(.int(32), 1))
        let thenBB = builder.buildBasicBlock(named: "then", arguments: [ "x" : .int(32) ], in: fun)
        let elseBB = builder.buildBasicBlock(named: "else", arguments: [ "x" : .int(32) ], in: fun)
        let contBB = builder.buildBasicBlock(named: "cont", arguments: [ "x" : .int(32) ], in: fun)
        builder.conditional(%cmp, then: thenBB, arguments: [.literal(.int(32), 0)],
                            else: elseBB, arguments: [.literal(.int(32), 1)])
        builder.move(to: thenBB)
        builder.branch(contBB, [ %thenBB.arguments[0] ])
        builder.move(to: elseBB)
        builder.branch(contBB, [ %elseBB.arguments[0] ])
        builder.move(to: contBB)
        builder.return(%contBB.arguments[0])
        
        /// Original:
        /// func @bar: (f32, f32) -> i32 {
        /// 'entry(%x: f32, %y : f32):
        ///     %0.0 = multiply 5: i32, 8: i32
        ///     %dead1 = multiply 10000: i32, 20000: i32
        ///     %dead2 = add %dead1: i32, 20000: i32
        ///     %0.3 = equal %v0: i32, 1: i32
        ///     conditional %v1: bool then 'then(0: i32) else 'else(1: i32)
        /// 'then(%x: i32):
        ///     branch 'cont(%x: i32)
        /// 'else(%x: i32):
        ///     branch 'cont(%x: i32)
        /// 'cont(%x: i32):
        ///     return %x: i32
        /// }
        builder.module.mapTransform(DeadCodeElimination.self)
        let after = """
            func @bar: (f32, f32) -> i32 {
            'entry(%x: f32, %y: f32):
                %0.0 = multiply 5: i32, 8: i32
                %0.1 = equal %0.0: i32, 1: i32
                conditional %0.1: bool then 'then(0: i32) else 'else(1: i32)
            'then(%x: i32):
                branch 'cont(%x: i32)
            'else(%x: i32):
                branch 'cont(%x: i32)
            'cont(%x: i32):
                return %x: i32
            }
            """
        XCTAssertEqual(fun.description, after)
        /// Reapplying shouldn't mutate the function
        
        let module = builder.module
        module.mapTransform(DeadCodeElimination.self)
        module.mapTransform(DeadCodeElimination.self)
        
        XCTAssertEqual(fun.description, after)
    }
    
    static var allTests : [(String, (TransformTests) -> () throws -> Void)] {
        return [
            ("testDCE", testDCE),
        ]
    }
    
}
