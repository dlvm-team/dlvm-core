//
//  Premise.swift
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

public protocol PremiseHolder : IRUnit {
    associatedtype Premise
    /// - TODO: Add constraints here (currently causing compiler crash)
    associatedtype PremiseVerifier : VerificationPass
    var premise: Premise { get }
}

public extension PremiseHolder
    where PremiseVerifier.Result == Premise, PremiseVerifier.Body == Self
{
    func verifyPremise() throws -> Premise {
        return try self.runVerification(PremiseVerifier.self)
    }

    var premise: Premise {
        do {
            return try verifyPremise()
        }
        catch {
            fatalError("""
                Found malformed IR while verifying properties:
                \(error)
                """)
        }
    }
}

extension BasicBlock : PremiseHolder {
    public struct Premise {
        public let first: Instruction
        public let terminator: Instruction
    }

    public enum PremiseVerifier : VerificationPass {
        public typealias Body = BasicBlock
        public typealias Result = Premise

        public static func run(on body: BasicBlock) throws -> Premise {
            guard let index = body.index(where: { $0.kind.isTerminator }) else {
                throw VerificationError.missingTerminator(body)
            }
            guard index == body.endIndex - 1 else {
                throw VerificationError.terminatorNotLast(body)
            }
            guard let entry = body.first else {
                throw VerificationError.noEntry(body)
            }
            return Premise(first: entry, terminator: body[index])
        }
    }
}

extension Function : PremiseHolder {
    public struct Premise {
        public let entry: BasicBlock
        public let exits: [(BasicBlock, Instruction)]
    }

    public enum PremiseVerifier : VerificationPass {
        public typealias Body = Function
        public typealias Result = Premise

        public static func run(on body: Function) throws -> Premise {
            var exits: [(BasicBlock, Instruction)] = []
            for bb in body {
                let terminator = try bb.verifyPremise().terminator
                if case .return = terminator.kind {
                    exits.append((bb, terminator))
                }
            }
            /// Entry must exist
            guard let entry = body.first else {
                throw VerificationError.noEntry(body)
            }
            return Premise(entry: entry, exits: exits)
        }
    }
}
