namespace InvoiceMatchingDemo {
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Measurement;

    // Convert Result -> Int
    function Bit(r : Result) : Int {
        return r == One ? 1 | 0;
    }

    // Map field value 1..4 to two bits [msb, lsb]
    function EncodeTwoBits(v : Int) : Int[] {
        // mapping: 1 -> 00, 2 -> 01, 3 -> 10, 4 -> 11
        if (v == 1) { return [0, 0]; }
        elif (v == 2) { return [0, 1]; }
        elif (v == 3) { return [1, 0]; }
        else { return [1, 1]; }
    }

    // Build 4-bit encoding [amt_msb, amt_lsb, date_msb, date_lsb]
    function EncodeInvoice(amt : Int, date : Int) : Int[] {
        let a = EncodeTwoBits(amt);
        let d = EncodeTwoBits(date);
        return [a[0], a[1], d[0], d[1]];
    }

    // Oracle: marks all basis states that match targetBits (length 4)
    operation OracleMatchPattern(allQubits : Qubit[], targetBits : Int[]) : Unit is Adj + Ctl {
        // We assume allQubits length == 4 and targetBits length == 4
        // Flip qubits where target bit == 0 so that matching states become |1111>
        for i in 0..3 {
            if (targetBits[i] == 0) {
                X(allQubits[i]);
            }
        }

        // Multi-controlled Z with first 3 as controls and last as target
        Controlled Z(allQubits[0..2], allQubits[3]);

        // Undo flips
        for i in 0..3 {
            if (targetBits[i] == 0) {
                X(allQubits[i]);
            }
        }
    }

    // Diffusion on 4 qubits
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

        // Precompute invoice encodings and count matches M
        mutable encodings = [];
        for i in 0..Length(invoices)-1 {
            let (_, amt, dt) = invoices[i];
            set encodings += [EncodeInvoice(amt, dt)];
        }

        // Choose target by classical values
        let targetAmount = 2;
        let targetDate   = 1;

        // Build target 4-bit pattern
        let targetPattern = EncodeInvoice(targetAmount, targetDate);
        // Example: amount=2 -> [0,1], date=1 -> [0,0] => [0,1,0,0] (0100)

        use qubits = Qubit[4];

        // Start in uniform superposition
        ApplyToEach(H, qubits);

        let N = Length(invoices);
        let iterations = GroverIterationsFromN(N);

        // Grover iterations
        for _ in 1..iterations {
            OracleMatchPattern(qubits, targetPattern);
            Diffusion(qubits);
        }

        // Measure
        let results = MeasureEachZ(qubits);
        ResetAll(qubits);

        // Convert measurement to 4-bit array (MSB first)
        let measuredBits = [
            Bit(results[0]),
            Bit(results[1]),
            Bit(results[2]),
            Bit(results[3])
        ];

        // Find first invoice whose encoding equals measuredBits
        mutable foundIdx = -1;
        for i in 0..Length(invoices)-1 {
            if (encodings[i] == measuredBits) {
                set foundIdx = i;
            }
        }

        if (foundIdx == -1) {
            Message("Measured pattern did not match any invoice (probabilistic outcome).");
            return "No match after measurement";
        }

        let (id, _, _) = invoices[foundIdx];
        Message($"Matched invoice: {id}");
        return id;
    }
}
