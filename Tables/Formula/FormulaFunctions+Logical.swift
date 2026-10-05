import Foundation

extension FormulaFunctions {
    static let logicalFunctions: [String: FunctionSpec] = [
        "TRUE": .constant { .boolean(true) },
        "FALSE": .constant { .boolean(false) },
        "NOT": FunctionSpec(1...1) { call throws(CellError) in .boolean(!(try call.boolean(0))) },
        "AND": FunctionSpec(1...255, lifts: .none) { call throws(CellError) in
            .boolean(try FormulaLogic.truths(call).allSatisfy { $0 })
        },
        "OR": FunctionSpec(1...255, lifts: .none) { call throws(CellError) in
            .boolean(try FormulaLogic.truths(call).contains(true))
        },
        "XOR": FunctionSpec(1...255, lifts: .none) { call throws(CellError) in
            .boolean(try FormulaLogic.truths(call).filter { $0 }.count % 2 == 1)
        },
        "IF": FunctionSpec(1...3, reference: { call throws(CellError) in
            let condition = try call.boolean(0)
            guard let reference = call.reference(condition ? 1 : 2) else { throw .valueError }
            return reference
        }, value: { call throws(CellError) in
            let condition = call.value(0)
            func branch(_ index: Int) -> FormulaValue {
                if index >= call.count { return .boolean(false) }
                return call.isMissing(index) ? .number(0) : call.value(index)
            }
            guard condition.isArray else {
                return try condition.single.coercedBoolean() ? branch(1) : branch(2)
            }
            // An array of conditions picks element by element.
            let chosen = [branch(1), branch(2)]
            return FormulaValue.lift([condition, chosen[0], chosen[1]]) { values in
                do throws(CellError) {
                    return try values[0].coercedBoolean() ? values[1] : values[2]
                } catch {
                    return .error(error)
                }
            }
        }),
        "IFS": FunctionSpec(2...254, lifts: .none) { call throws(CellError) in
            guard call.count % 2 == 0 else { throw .valueError }
            var index = 0
            while index + 1 < call.count {
                if try call.boolean(index) { return call.isMissing(index + 1) ? .number(0) : call.value(index + 1) }
                index += 2
            }
            throw .notAvailable
        },
        "SWITCH": FunctionSpec(3...254, lifts: .none) { call throws(CellError) in
            let subject = call.scalar(0)
            if let error = subject.errorValue { throw error }
            var index = 1
            while index + 1 < call.count {
                let candidate = call.scalar(index)
                if let error = candidate.errorValue { throw error }
                if FormulaComparison.equal(candidate, subject) { return call.value(index + 1) }
                index += 2
            }
            // A leftover trailing argument is the default result.
            guard call.count % 2 == 0 else { throw .notAvailable }
            return call.value(call.count - 1)
        },
        "IFERROR": FunctionSpec(2...2, lifts: .none) { call throws(CellError) in
            FormulaLogic.trap(call) { _ in true }
        },
        "IFNA": FunctionSpec(2...2, lifts: .none) { call throws(CellError) in
            FormulaLogic.trap(call) { $0 == .notAvailable }
        },
    ]
}

enum FormulaLogic {
    /// The truth values `AND`, `OR` and `XOR` combine. In ranges and arrays
    /// text and blanks are passed over; typed into the call, text must read
    /// as TRUE or FALSE. With nothing to combine the answer is `#VALUE!`.
    static func truths(_ call: FunctionCall) throws(CellError) -> [Bool] {
        var result: [Bool] = []
        for index in 0..<call.count where !call.isMissing(index) {
            let value = call.value(index)
            if call.isReference(index) || value.isMatrix {
                for cell in value.flattened {
                    switch cell {
                    case .boolean(let flag): result.append(flag)
                    case .number(let number): result.append(number != 0)
                    case .error(let error): throw error
                    case .text, .empty: break
                    }
                }
            } else {
                result.append(try value.single.coercedBoolean())
            }
        }
        guard !result.isEmpty else { throw .valueError }
        return result
    }

    /// `IFERROR` and `IFNA`: the first argument, with the errors `catches`
    /// accepts replaced by the second, element by element over an array.
    static func trap(_ call: FunctionCall, catches: (CellError) -> Bool) -> FormulaValue {
        let primary = call.value(0)
        let fallback = call.isMissing(1) ? FormulaValue.number(0) : call.value(1)
        guard primary.isArray else {
            if let error = primary.single.errorValue, catches(error) { return fallback }
            return primary
        }
        return FormulaValue.lift([primary, fallback]) { values in
            if let error = values[0].errorValue, catches(error) { return values[1] }
            return values[0]
        }
    }
}
