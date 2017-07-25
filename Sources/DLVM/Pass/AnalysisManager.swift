//
//  AnalysisManager.swift
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

internal struct PreservedAnalyses {
    private typealias ID = ObjectIdentifier

    private var analysisMap: [ID : Any] = [:]

    func result<Pass : AnalysisPass>(from _: Pass.Type) -> Pass.Result? {
        /// If result is cached, return it
        return analysisMap[ID(Pass.self)] as? Pass.Result
    }

    func containsResult<Pass : AnalysisPass>(from type: Pass.Type) -> Bool {
        return result(from: type) != nil
    }

    mutating func insert<Pass : AnalysisPass>(_ result: Pass.Result,
                                              for type: Pass.Type) {
        analysisMap[ID(type)] = result
    }

    mutating func removeResult<Pass : AnalysisPass>(from type: Pass.Type) -> Pass.Result? {
        return analysisMap.removeValue(forKey: ID(type)) as? Pass.Result
    }

    mutating func removeAll() {
        analysisMap.removeAll()
    }
}

public class AnalysisManager<Body> {
    fileprivate var analyses: PreservedAnalyses = PreservedAnalyses()
    internal init() {}
}

public extension AnalysisManager {
    func invalidateAll() {
        analyses.removeAll()
    }

    @discardableResult
    func invalidateAnalysis<Pass : AnalysisPass>(from pass: Pass.Type) -> Pass.Result? {
        return analyses.removeResult(from: pass)
    }

    func updateAnalysis<Pass : AnalysisPass>(_ result: Pass.Result, from pass: Pass.Type) {
        analyses.insert(result, for: pass)
    }

    func analysis<Pass : AnalysisPass>(from pass: Pass.Type) -> Pass.Result? {
        return analyses.result(from: pass)
    }
}

public protocol AnalysisCacheable {
    var analysisManager: AnalysisManager<Self> { get }
    func invalidateAnalyses()
}

public extension IRCollection {
    func analysis<P : AnalysisPass>(from _: P.Type) throws -> P.Result
        where P.Body == Self
    {
        if let result = analysisManager.analysis(from: P.self) {
            return result
        }
        let result = try P.run(on: self)
        analysisManager.updateAnalysis(result, from: P.self)
        return result
    }
}

extension AnalysisCacheable {
    func invalidateLocalAnalyses() {
        analysisManager.invalidateAll()
    }
}

extension Module : AnalysisCacheable {
    public func invalidateAnalyses() {
        invalidateLocalAnalyses()
        for child in self {
            child.invalidateLocalAnalyses()
            for grandchild in self {
                grandchild.invalidateLocalAnalyses()
            }
        }
    }
}

extension Function : AnalysisCacheable {
    public func invalidateAnalyses() {
        invalidateLocalAnalyses()
        parent.invalidateLocalAnalyses()
        for child in self {
            child.invalidateLocalAnalyses()
        }
    }
}

extension BasicBlock : AnalysisCacheable {
    public func invalidateAnalyses() {
        invalidateLocalAnalyses()
        parent.invalidateLocalAnalyses()
        parent.parent.invalidateLocalAnalyses()
    }
}
