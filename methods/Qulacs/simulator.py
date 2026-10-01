import sys
import qulacs as qu
from math import pi


def num(s: str) -> int:
    return int(''.join(c for c in s if c.isdigit()))


def qasm_to_qalacs(qasm: str) -> tuple[qu.QuantumCircuit, int]:
    """
    returns the circuit, and the number of qubits.
    Supports only X, H, S, T, CNOT, and R_x(pi/2) gates
    """
    qasm = qasm.split(';')
    n = num(qasm[2])
    circuit = qu.QuantumCircuit(n)

    for line in qasm[3:-1]:  # first 3 lines are metadata, last is empty, these are skipped
        line = line.split()
        match line[0]:
            case 'x':
                target = num(line[1])
                circuit.add_X_gate(target)
            case 'h':
                target = num(line[1])
                circuit.add_H_gate(target)
            case 's':
                target = num(line[1])
                circuit.add_S_gate(target)
            case 't':
                target = num(line[1])
                circuit.add_T_gate(target)
            case 'cx':
                control = num(line[1])
                target = num(line[2])
                circuit.add_CNOT_gate(control, target)
            case 'rx(0.5*pi)':
                target = num(line[1])
                circuit.add_RotX_gate(target, pi/2)
            case _:
                raise ValueError(f'gate {line[0]} not of supported types')

    return circuit, n


def run(circuit_file: str):
    with open(circuit_file, 'r') as f:
        qasm = f.read()

    circuit, n = qasm_to_qalacs(qasm)
    state = qu.QuantumState(n)
    effect = qu.QuantumState(n)

    circuit.update_quantum_state(state)
    return qu.state.inner_product(effect, state)


def main():
    # if len(sys.argv) != 2:
    #    print("Usage: simulator.py <circuit_file>")
    #    sys.exit(1)
    amplitude = run(sys.argv[1])
    print(amplitude)


if __name__ == "__main__":
    main()
