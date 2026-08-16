import sys

from qiskit import qasm2
from qiskit_aer.quantum_info import AerStatevector


def run(circuit_file: str):
    with open(circuit_file, "r") as f:
        qasm = f.read()

    circuit = qasm2.loads(qasm)

    statevector = AerStatevector(circuit)

    # <0...0| C |0...0>
    return complex(statevector.data[0])


def main():
    amplitude = run(sys.argv[1])
    print(amplitude)


if __name__ == "__main__":
    main()