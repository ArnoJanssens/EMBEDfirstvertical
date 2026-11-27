import math

# ============================================================
# CONFIGURATION
# ============================================================

N = 8
COEFF_WIDTH = 16
FRAC = 15

USE_SYMMETRY = False

FILENAME = "hdl/hann.mem"

# ============================================================
# GENERATE WINDOW COEFFICIENTS
# ============================================================

coefficients = []

for n in range(N):

    # Calculate Hann window coefficient
    w = 0.5 * (1 - math.cos(2 * math.pi * n / (N - 1)))

    # Convert to unsigned UQ1.15
    coefficient = round(w * 2**FRAC)

    coefficients.append(coefficient)

# ============================================================
# EXPORT TO MEMORY FILE
# ============================================================

if USE_SYMMETRY:
    num_coefficients = N // 2
else:
    num_coefficients = N

hex_digits = (COEFF_WIDTH + 3) // 4

with open(FILENAME, "w") as file:

    for n in range(num_coefficients):

        coefficient = coefficients[n]

        file.write(f"{coefficient:0{hex_digits}X}\n")

# ============================================================
# INFORMATION
# ============================================================

print("Window size:", N)
print("Stored coefficients:", num_coefficients)
print("Coefficient width:", COEFF_WIDTH)
print("Fractional bits:", FRAC)
print("Minimum coefficient:", min(coefficients))
print("Maximum coefficient:", max(coefficients))
print("ROM size:", num_coefficients * COEFF_WIDTH, "bits")
print("Generated file:", FILENAME)