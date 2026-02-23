namespace InvoiceMatchingDemo {
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Measurement;

    // Convert Result -> Int
    function Bit(r : Result) : Int {
        return r == One ? 1 | 0;
    }

    // Convert integer index (0–15) to 4-bit array
    function IntToBits4(n : Int) : Int[] {
        return [
            (n >>> 3) &&& 1,
            (n >>> 2) &&& 1,
            (n >>> 1) &&& 1,
            n &&& 1
        ];
    }

    // Oracle: marks exactly one basis state
    operation Oracle(allQubits : Qubit[], targetIndex : Int) : Unit is Adj + Ctl {
        let bits = IntToBits4(targetIndex);

        // Flip qubits where target bit = 0
        for i in 0..3 {
            if (bits[i] == 0) {
                X(allQubits[i]);
            }
        }

        // Multi-controlled Z
        Controlled Z(allQubits[0..2], allQubits[3]);

        // Undo flips
        for i in 0..3 {
            if (bits[i] == 0) {
                X(allQubits[i]);
            }
        }
    }

    // Perfect diffusion operator
    operation Diffusion(allQubits : Qubit[]) : Unit {
        ApplyToEach(H, allQubits);
        ApplyToEach(X, allQubits);

        Controlled Z(allQubits[0..2], allQubits[3]);
 
        ApplyToEach(X, allQubits);
        ApplyToEach(H, allQubits);
    }

    // Integer square root: returns the largest k such that k*k <= n
    function IntSqrt(n : Int) : Int {
        mutable k = 0;
        // Guard for non-positive n
        if (n <= 0) {
            return 0;
        }
        // Simple incremental search; fine for small N in demos
        // For larger N, you could replace with a binary search.
        while ((k + 1) * (k + 1) <= n) {
            set k = k + 1;
        }
        return k;
    }

    // Integer-only approximation: iterations ≈ floor((pi/4) * sqrt(N))
    // Use π/4 ≈ 0.785398 via scaled integer arithmetic: (k * 785398) / 1000000
    function GroverIterationsFromN(n : Int) : Int {
        let k = IntSqrt(n);
        return (k * 785398) / 1000000;
    }

    @EntryPoint()
    operation RunGroverInvoiceMatch() : String {

        // Classical invoice dataset
        let invoices = [
            ("INV-2026-001", 2, 3),
            ("INV-2026-002", 4, 1),
            ("INV-2026-003", 2, 4),
            ("INV-2026-004", 1, 3),
            ("INV-2026-005", 1, 1),
            ("INV-2026-006", 1, 2),
            ("INV-2026-007", 1, 4),
            ("INV-2026-008", 2, 1),
            ("INV-2026-009", 2, 2),
            ("INV-2026-010", 3, 1),
            ("INV-2026-011", 3, 2),
            ("INV-2026-012", 3, 3),
            ("INV-2026-013", 3, 4),
            ("INV-2026-014", 4, 2),
            ("INV-2026-015", 4, 3),
            ("INV-2026-016", 4, 4)
        ];

        // Choose target by classical matching
        let targetAmount = 2;
        let targetDate   = 1;

        mutable targetIndex = 0;
        for i in 0..Length(invoices)-1 {
            let (_, amt, dt) = invoices[i];
            if (amt == targetAmount and dt == targetDate) {
                set targetIndex = i;
            }
        }

        use qubits = Qubit[4];

        // Start in uniform superposition
        ApplyToEach(H, qubits);

        let N = Length(invoices);
        let iterations = GroverIterationsFromN(N);

        // Grover iterations
        for _ in 1..iterations {
            Oracle(qubits, targetIndex);
            Diffusion(qubits);
        }

        // Measure
        let results = MeasureEachZ(qubits);
        ResetAll(qubits);

        // Convert measurement to integer index
        let idx =
            Bit(results[0]) * 8 +
            Bit(results[1]) * 4 +
            Bit(results[2]) * 2 +
            Bit(results[3]) * 1;

        let (id, _, _) = invoices[idx];

        Message($"Matched invoice: {id}");
        return id;
    }
}
