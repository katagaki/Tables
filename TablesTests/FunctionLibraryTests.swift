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

@Suite("Descriptive statistics")
struct DescriptiveStatisticsTests {
    @Test("Spread and shape match Excel's documented examples")
    func shape() {
        let data = "{3,4,5,2,3,4,5,6,4,7}"
        #expect(close(evaluate("=KURT(\(data))"), -0.151799637, tolerance: 1e-8))
        #expect(close(evaluate("=SKEW(\(data))"), 0.359543071, tolerance: 1e-8))
        #expect(close(evaluate("=SKEW.P(\(data))"), 0.303193339, tolerance: 1e-8))
        #expect(close(evaluate("=TRIMMEAN({4,5,6,7,2,3,4,5,1,2,3},0.2)"), 3.777777778, tolerance: 1e-8))
        #expect(close(evaluate("=AVEDEV({4,5,6,7,5,4,3})"), 1.020408163, tolerance: 1e-8))
        #expect(evaluate("=DEVSQ({4,5,8,7,11,4,3})") == .number(48))
        #expect(close(evaluate("=GEOMEAN({4,5,8,7,11,4,3})"), 5.476986969, tolerance: 1e-8))
        #expect(close(evaluate("=HARMEAN({4,5,8,7,11,4,3})"), 5.028375962, tolerance: 1e-8))
        let sample = "{1345,1301,1368,1322,1310,1370,1318,1350,1303,1299}"
        #expect(close(evaluate("=STDEV.P(\(sample))"), 26.05455814, tolerance: 1e-8))
        #expect(close(evaluate("=STDEV.S(\(sample))"), 27.46391572, tolerance: 1e-8))
        #expect(close(evaluate("=VARA({1,TRUE,\"x\"})"), 1.0 / 3))
    }

    @Test("Percentiles, quartiles and percent ranks")
    func percentiles() {
        #expect(close(evaluate("=PERCENTILE.INC({1,3,2,4},0.3)"), 1.9))
        #expect(close(evaluate("=PERCENTILE.EXC({1,2,3,6,6,6,7,8,9},0.25)"), 2.5))
        #expect(evaluate("=PERCENTILE.EXC({1,2,3},0.1)") == .error(.numberError))
        #expect(close(evaluate("=QUARTILE.INC({1,2,4,7,8,9,10,12},1)"), 3.5))
        #expect(close(evaluate("=QUARTILE.EXC({6,7,15,36,39,40,41,42,43,47,49},1)"), 15))
        let ranks = "{13,12,11,8,4,3,2,1,1,1}"
        #expect(evaluate("=PERCENTRANK.INC(\(ranks),2)") == .number(0.333))
        #expect(evaluate("=PERCENTRANK.INC(\(ranks),4)") == .number(0.555))
        #expect(evaluate("=PERCENTRANK.INC(\(ranks),5)") == .number(0.583))
        #expect(evaluate("=PERCENTRANK.EXC({1,2,3,6,6,6,7,8,9},7)") == .number(0.7))
        #expect(evaluate("=PERCENTRANK.EXC({1,2,3,6,6,6,7,8,9},5.43)") == .number(0.381))
        #expect(evaluate("=PERCENTRANK.EXC({1,2,3,6,6,6,7,8,9},5.43,1)") == .number(0.3))
    }

    @Test("Ranks, modes and frequencies")
    func ranks() {
        #expect(evaluate("=RANK.EQ(7,{7,3.5,3.5,1,2})") == .number(1))
        #expect(evaluate("=RANK.EQ(2,{7,3.5,3.5,1,2},1)") == .number(2))
        #expect(evaluate("=RANK.AVG(3.5,{7,3.5,3.5,1,2})") == .number(2.5))
        #expect(evaluate("=RANK(9,{7,3.5})") == .error(.notAvailable))
        #expect(evaluate("=MODE.SNGL({5.6,4,4,3,2,4})") == .number(4))
        #expect(evaluate("=MODE({1,2,3})") == .error(.notAvailable))
        #expect(evaluate("=TEXTJOIN(\",\",,MODE.MULT({1,2,3,4,3,2,1,2,3,5,6,1}))") == .text("1,2,3"))
        #expect(evaluate("=TEXTJOIN(\",\",,FREQUENCY({79,85,78,85,50,81,95,88,97},{70,79,89}))") == .text("1,2,4,2"))
        #expect(evaluate("=MAXIFS({89,93,96,85,91,88},{1,2,2,3,1,1},1)") == .number(91))
        #expect(evaluate("=MINIFS({89,93,96,85,91,88},{1,2,2,3,1,1},2)") == .number(93))
    }

    @Test("Correlation, covariance and simple regression")
    func pairs() {
        #expect(close(evaluate("=CORREL({3,2,4,5,6},{9,7,12,15,17})"), 0.997054486, tolerance: 1e-8))
        #expect(close(evaluate("=COVARIANCE.P({3,2,4,5,6},{9,7,12,15,17})"), 5.2))
        #expect(close(evaluate("=COVARIANCE.S({3,2,4,5,6},{9,7,12,15,17})"), 6.5))
        let ys = "{2,3,9,1,8,7,5}"
        let xs = "{6,5,11,7,5,4,4}"
        #expect(close(evaluate("=SLOPE(\(ys),\(xs))"), 0.305555556, tolerance: 1e-8))
        #expect(close(evaluate("=INTERCEPT({2,3,9,1,8},{6,5,11,7,5})"), 0.048387097, tolerance: 1e-7))
        #expect(close(evaluate("=RSQ(\(ys),\(xs))"), 0.057950192, tolerance: 1e-7))
        #expect(close(evaluate("=STEYX(\(ys),\(xs))"), 3.305718950, tolerance: 1e-8))
        #expect(close(evaluate("=FORECAST(30,{6,7,9,15,21},{20,28,31,38,40})"), 10.607253, tolerance: 1e-7))
        #expect(close(evaluate("=FORECAST.LINEAR(30,{6,7,9,15,21},{20,28,31,38,40})"), 10.607253, tolerance: 1e-7))
    }

    @Test("Multiple regression and growth curves")
    func regression() {
        #expect(close(evaluate("=INDEX(LINEST({1,9,5,7},{0,4,2,3}),1,1)"), 2))
        #expect(close(evaluate("=INDEX(LINEST({1,9,5,7},{0,4,2,3}),1,2)"), 1))
        #expect(close(evaluate("=TREND({1,2,3},{1,2,3},4)"), 4))
        let sales = "{33100,47300,69000,102000,150000,220000}"
        let months = "{11,12,13,14,15,16}"
        #expect(close(evaluate("=GROWTH(\(sales),\(months),17)"), 320196.7184, tolerance: 1e-8))
        #expect(close(evaluate("=INDEX(LOGEST(\(sales),\(months)),1,1)"), 1.463275628, tolerance: 1e-8))
        #expect(close(evaluate("=INDEX(LOGEST(\(sales),\(months)),1,2)"), 495.3047702, tolerance: 1e-7))
        // Two predictors, with statistics.
        let y = "{1;2;3;5;8}"
        let x = "{1,2;2,1;3,4;4,3;5,7}"
        #expect(close(evaluate("=INDEX(LINEST(\(y),\(x),TRUE,TRUE),3,1)"), 0.9574102368220015))
        #expect(close(evaluate("=INDEX(LINEST(\(y),\(x)),1,1)"), 0.29411764705882354))
        #expect(close(evaluate("=INDEX(LINEST(\(y),\(x)),1,2)"), 1.3470588235294119))
        #expect(close(evaluate("=INDEX(LINEST(\(y),\(x)),1,3)"), -1.2411764705882353))
        #expect(evaluate("=INDEX(LINEST(\(y),\(x),TRUE,TRUE),3,3)") == .error(.notAvailable))
    }

    @Test("Standardising, Fisher transforms, permutations and probability")
    func odds() {
        #expect(close(evaluate("=STANDARDIZE(42,40,1.5)"), 1.333333333, tolerance: 1e-8))
        #expect(close(evaluate("=FISHER(0.75)"), 0.972955075, tolerance: 1e-8))
        #expect(close(evaluate("=FISHERINV(0.972955075)"), 0.75, tolerance: 1e-8))
        #expect(evaluate("=PERMUT(100,3)") == .number(970200))
        #expect(evaluate("=PERMUTATIONA(3,2)") == .number(9))
        #expect(close(evaluate("=PROB({0,1,2,3},{0.2,0.3,0.1,0.4},2)"), 0.1))
        #expect(close(evaluate("=PROB({0,1,2,3},{0.2,0.3,0.1,0.4},1,3)"), 0.8))
    }
}
