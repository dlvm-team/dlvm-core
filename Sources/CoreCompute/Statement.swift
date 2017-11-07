//
//  Statement.swift
//  DLVM
//
//  Copyright 2016-2017 Richard Wei.
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

import CoreOp

public indirect enum Statement {
    case `let`(String, Expression, body: Statement)
    case assert(Expression, message: Expression)
    case producer(Computation, Statement)
    case consumer(Computation, Statement)
    case store(Expression, index: Expression, predicate: Expression)
    case provide(Computation, index: Int, value: Expression, arguments: [Expression])
    case allocate(Variable, Type, extents: [Expression], condition: Expression)
    case free(Variable)
    case realize(
        Computation, index: Int, Type, bounds: CountableRange<UInt>,
        condition: Expression, body: Statement)
    case block([Statement])
    case `if`(Expression, then: Statement, `else`: Statement)
    case evaluate(Expression)
    case apply(Computation, [Expression])
    case call(CallKind, String, [Expression])
    case `for`(ForKind, Variable, bounds: CountableRange<UInt>, body: Statement)
    case shuffle([Expression], indices: [Expression])
    case prefetch(Computation, index: Int, type: Type, bounds: CountableRange<UInt>)
}

public enum CallKind : Equatable {
    case extern
    case externCXX
    case pureExtern
    case intrinsic
    case pureIntrinsic
}

public enum ForKind : Equatable {
    case serial
    case parallel
    case vectorized
    case unrolled
}

extension Statement : Equatable {
    public static func == (lhs: Statement, rhs: Statement) -> Bool {
        switch (lhs, rhs) {
        case let (.let(n1, e1, body: b1), .let(n2, e2, body: b2)):
            return n1 == n2 && e1 == e2 && b1 == b2
        case let (.assert(e1, message: m1), .assert(e2, message: m2)):
            return e1 == e2 && m1 == m2
        case let (.producer(c1, s1), .producer(c2, s2)):
            return c1 == c2 && s1 == s2
        case let (.consumer(c1, s1), .consumer(c2, s2)):
            return c1 == c2 && s1 == s2
        case let (.store(e1, index: i1, predicate: p1), .store(e2, index: i2, predicate: p2)):
            return e1 == e2 && i1 == i2 && p1 == p2
        case let (.provide(c1, index: i1, value: v1, arguments: aa1),
                  .provide(c2, index: i2, value: v2, arguments: aa2)):
            return c1 == c2 && i1 == i2 && v1 == v2 && aa1 == aa2
        case let (.allocate(v1, t1, extents: ee1, condition: c1),
                  .allocate(v2, t2, extents: ee2, condition: c2)):
            return v1 == v2 && t1 == t2 && ee1 == ee2 && c1 == c2
        case let (.free(v1), .free(v2)):
            return v1 == v2
        case let (.realize(f1, index: i1, t1, bounds: r1, condition: c1, body: b1),
                  .realize(f2, index: i2, t2, bounds: r2, condition: c2, body: b2)):
            return f1 == f2 && i1 == i2 && t1 == t2 && r1 == r2 && c1 == c2 && b1 == b2
        case let (.block(ss1), .block(ss2)):
            return ss1 == ss2
        case let (.if(cond1, then: then1, else: else1), .if(cond2, then: then2, else: else2)):
            return cond1 == cond2 && then1 == then2 && else1 == else2
        case let (.evaluate(e1), .evaluate(e2)):
            return e1 == e2
        case let (.apply(f1, args1), .apply(f2, args2)):
            return f1 == f2 && args1 == args2
        case let (.call(k1, n1, args1), .call(k2, n2, args2)):
            return k1 == k2 && n1 == n2 && args1 == args2
        case let (.for(k1, v1, bounds: r1, body: b1), .for(k2, v2, bounds: r2, body: b2)):
            return k1 == k2 && v1 == v2 && r1 == r2 && b1 == b2
        case let (.shuffle(ee1, indices: ii1), .shuffle(ee2, indices: ii2)):
            return ee1 == ee2 && ii1 == ii2
        case let (.prefetch(f1, index: i1, type: t1, bounds: r1),
                  .prefetch(f2, index: i2, type: t2, bounds: r2)):
            return f1 == f2 && i1 == i2 && t1 == t2 && r1 == r2
        default:
            return false
        }
    }
}
