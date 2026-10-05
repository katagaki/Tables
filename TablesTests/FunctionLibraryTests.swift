import Foundation
import Testing
@testable import Tables

/// Whether a number is within a relative tolerance of what Excel gives.
func close(_ value: CellValue, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    guard case .number(let actual) = value else { return false }
    return abs(actual - expected) <= tolerance * max(1, abs(expected))
}

@Suite("Math and trigonometry")
struct MathFunctionTests {
    @Test("Hyperbolic and reciprocal trigonometry")
    func trigonometry() {
        #expect(close(evaluate("=SINH(1)"), 1.1752011936438014))
        #expect(close(evaluate("=ACOSH(2)"), 1.3169578969248166))
        #expect(evaluate("=ACOSH(0.5)") == .error(.numberError))
        #expect(close(evaluate("=ACOT(2)"), 0.4636476090008061))
        #expect(close(evaluate("=ACOTH(3)"), 0.34657359027997264))
        #expect(close(evaluate("=COT(1)"), 0.6420926159343306))
        #expect(evaluate("=COT(0)") == .error(.divideByZero))
        #expect(close(evaluate("=CSC(1)"), 1.1883951057781212))
        #expect(close(evaluate("=SEC(1)"), 1.8508157176809255))
        #expect(close(evaluate("=SECH(1)"), 0.6480542736638855))
        #expect(close(evaluate("=SQRTPI(2)"), 2.5066282746310002))
    }

    @Test("Rounding to multiples and parity")
    func multiples() {
        #expect(evaluate("=CEILING.MATH(-2.5,2)") == .number(-2))
        #expect(evaluate("=CEILING.MATH(-2.5,2,1)") == .number(-4))
        #expect(evaluate("=FLOOR.MATH(-2.5,2)") == .number(-4))
        #expect(evaluate("=FLOOR.MATH(-2.5,2,1)") == .number(-2))
        #expect(evaluate("=CEILING.PRECISE(4.3,-2)") == .number(6))
        #expect(evaluate("=FLOOR.PRECISE(-3.2,-1)") == .number(-4))
        #expect(evaluate("=MROUND(10,3)") == .number(9))
        #expect(evaluate("=MROUND(-10,-3)") == .number(-9))
        #expect(evaluate("=MROUND(5,-2)") == .error(.numberError))
        #expect(evaluate("=EVEN(1.5)") == .number(2))
        #expect(evaluate("=EVEN(-1)") == .number(-2))
        #expect(evaluate("=ODD(0)") == .number(1))
        #expect(evaluate("=ODD(-2)") == .number(-3))
        #expect(evaluate("=QUOTIENT(-10,3)") == .number(-3))
    }

    @Test("Counting and combinatorics")
    func combinatorics() {
        #expect(evaluate("=FACT(5)") == .number(120))
        #expect(evaluate("=FACT(-1)") == .error(.numberError))
        #expect(evaluate("=FACTDOUBLE(7)") == .number(105))
        #expect(evaluate("=COMBIN(8,2)") == .number(28))
        #expect(evaluate("=COMBINA(4,3)") == .number(20))
        #expect(evaluate("=MULTINOMIAL(2,3,4)") == .number(1260))
        #expect(evaluate("=GCD(24,36,60)") == .number(12))
        #expect(evaluate("=LCM(4,6,10)") == .number(60))
        #expect(evaluate("=GCD(-1,2)") == .error(.numberError))
    }

    @Test("Sums of squares and series")
    func sums() {
        #expect(evaluate("=SUMSQ(3,4)") == .number(25))
        #expect(evaluate("=SUMX2MY2({2,3},{1,1})") == .number(11))
        #expect(evaluate("=SUMX2PY2({2,3},{1,1})") == .number(15))
        #expect(evaluate("=SUMXMY2({2,3},{1,1})") == .number(5))
        #expect(evaluate("=SERIESSUM(2,0,1,{1,1,1})") == .number(7))
        #expect(evaluate("=PERCENTOF({1,3},{1,3,4,2})") == .number(0.4))
    }

    @Test("Roman numerals in every form, and number bases")
    func numerals() {
        #expect(evaluate("=ROMAN(499)") == .text("CDXCIX"))
        #expect(evaluate("=ROMAN(499,1)") == .text("LDVLIV"))
        #expect(evaluate("=ROMAN(499,2)") == .text("XDIX"))
        #expect(evaluate("=ROMAN(499,3)") == .text("VDIV"))
        #expect(evaluate("=ROMAN(499,4)") == .text("ID"))
        #expect(evaluate("=ROMAN(1994)") == .text("MCMXCIV"))
        #expect(evaluate("=ARABIC(\"mcmxciv\")") == .number(1994))
        #expect(evaluate("=ARABIC(\"ID\")") == .number(499))
        #expect(evaluate("=BASE(255,16,4)") == .text("00FF"))
        #expect(evaluate("=BASE(7,2)") == .text("111"))
        #expect(evaluate("=DECIMAL(\"FF\",16)") == .number(255))
        #expect(evaluate("=DECIMAL(\"zz\",36)") == .number(1295))
    }

    @Test("Matrices")
    func matrices() {
        #expect(evaluate("=SUM(MMULT({1,2;3,4},{5;6}))") == .number(56))
        #expect(evaluate("=MMULT({1,2},{1,2})") == .error(.valueError))
        #expect(close(evaluate("=MDETERM({1,3,8,5;1,3,6,1;1,1,1,0;7,3,10,2})"), 88))
        #expect(close(evaluate("=INDEX(MINVERSE({4,-1;2,1}),1,2)"), 1.0 / 6))
        #expect(evaluate("=MINVERSE({1,2;2,4})") == .error(.numberError))
        #expect(evaluate("=SUM(MUNIT(3))") == .number(3))
    }

    @Test("SEQUENCE and RANDARRAY generate arrays")
    func generators() {
        #expect(evaluate("=SUM(SEQUENCE(4))") == .number(10))
        #expect(evaluate("=INDEX(SEQUENCE(2,3,10,5),2,1)") == .number(25))
        #expect(evaluate("=COUNT(RANDARRAY(3,2,1,6,TRUE))") == .number(6))
    }
}
