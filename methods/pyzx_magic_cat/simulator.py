import sys
import pyzx as zx
from pyzx.simulation import Strategy

def run(circuit_file: str):
    with open(circuit_file, "r") as f:
        seed = int(f.read().strip()) #TEMP (for now, just read a seed rather than a circuit)
        print("seed:",seed) #TEMP
    q, d = 10, 300
    g = zx.generate.cliffordT(qubits=q,depth=d,seed=seed)
    g.apply_state("0"*q)
    g.apply_effect("0"*q)
    zx.simplify.full_reduce(g)

    return zx.simulation.simulate(Strategy.BSS, g) #TEMP (should be magic_cat)

def main():
    #if len(sys.argv) != 2:
    #    print("Usage: simulator.py <circuit_file>")
    #    sys.exit(1)
    amplitude = run(sys.argv[1])
    print(amplitude)

if __name__ == "__main__":
    main()