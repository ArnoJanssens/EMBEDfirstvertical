import numpy as np
import matplotlib.pyplot as plt
import sounddevice as sd
from matplotlib.animation import FuncAnimation
from matplotlib.colors import LinearSegmentedColormap

# ============================================================
# CONFIGURATION
# ============================================================

FS = 48000
N = 1024
STAGES = 10
Q = 15

# FFT bin boundaries (end exclusive), approximately:
# 0-125, 125-250, 250-500, 500-1000, 1000-2000,
# 2000-4000, 4000-8000, 8000-24000 Hz.
# Start at bin 1 to ignore the DC component.
BIN_EDGES = (1, 3, 6, 11, 22, 43, 86, 171, 513)

# Per-band gains in Q8.8 format (256 means 1x). -> can implement as shift right
BAND_GAIN_Q8 = (128, 256, 256, 512, 512, 1024, 1024, 1024)

# Display range in dBFS. Logarithms are used only while
# preparing constants, never during audio processing.
DB_MIN = -65
DB_MAX = -15
LEVEL_MAX = 8 * 256


# ============================================================
# PRECOMPUTED LOOKUP TABLES (ROM IN FPGA)
# ============================================================
#TODO make this less complex
def make_power_thresholds():
    thresholds = []
    full_scale_power = (32767 / 2) ** 2 #16 bit signed integer power range

    for level in range(LEVEL_MAX + 1): 
        db = DB_MIN + (DB_MAX - DB_MIN) * level / LEVEL_MAX
        power = full_scale_power * 10 ** (db / 10)
        thresholds.append(int(round(power)))

    return thresholds #power thresholds for the bar diagram, too overcomplicated for now


def make_twiddle_rom(): #precalculate twiddle factors -> OK, will include into ROM memory
    rom = []

    for stage in range(STAGES):
        stage_twiddles = []
        group_size = 1 << (stage + 1)
        half_size = group_size >> 1

        for k in range(half_size):
            angle = 2 * np.pi * k / group_size
            real = int(round(np.cos(angle) * 32767))
            imag = int(round(-np.sin(angle) * 32767))
            stage_twiddles.append((real, imag))

        rom.append(stage_twiddles)

    return rom


def make_bit_reverse(): #can also be included in memory, but not sure
    addresses = []

    for address in range(N):
        reversed_address = 0

        for bit in range(STAGES):
            bit_value = (address >> bit) & 1
            reversed_address = (reversed_address << 1) | bit_value

        addresses.append(reversed_address)

    return addresses


POWER_THRESHOLDS = make_power_thresholds()
TWIDDLE_ROM = make_twiddle_rom()
BIT_REVERSE = make_bit_reverse()


# ============================================================
# FIXED-POINT RADIX-2 FFT
# ============================================================

def fft_fixed(audio):
    """1024-point radix-2 DIT FFT with Q1.15 twiddle factors.

    Each butterfly stage shifts its results right by one bit.
    Python integers do not overflow, unlike fixed-width FPGA registers.
    """
    real = [0] * N
    imag = [0] * N

    # Copy input samples into bit-reversed order.
    for i in range(N):
        real[i] = int(audio[BIT_REVERSE[i]])
        #input is purely real so no imaginary numbers

    for stage in range(STAGES):
        group_size = 1 << (stage + 1)
        half_size = group_size >> 1

        for group in range(0, N, group_size):
            for k in range(half_size):
                i = group + k
                j = i + half_size

                twiddle_real, twiddle_imag = TWIDDLE_ROM[stage][k]

                # Complex multiplication, followed by Q1.15 scaling.
                product_real = (twiddle_real * real[j] - twiddle_imag * imag[j]) >> Q
                product_imag = (twiddle_real * imag[j] + twiddle_imag * real[j]) >> Q

                upper_real = real[i]
                upper_imag = imag[i]

                # Butterfly outputs; shift once per stage to avoid growth.
                real[i] = (upper_real + product_real) >> 1
                imag[i] = (upper_imag + product_imag) >> 1
                real[j] = (upper_real - product_real) >> 1
                imag[j] = (upper_imag - product_imag) >> 1

    return real, imag


# ============================================================
# BAND POWER AND LED LEVELS
# ============================================================

def power_to_level(power):
    """Find an LED level (0..2048) using integer comparisons."""
    low = 0
    high = LEVEL_MAX

    while low < high:
        middle = (low + high + 1) >> 1

        if power >= POWER_THRESHOLDS[middle]:
            low = middle
        else:
            high = middle - 1

    return low


def process(audio, previous):
    real, imag = fft_fixed(audio)
    levels = [0] * 8

    for band in range(8):
        peak_power = 0
        first_bin = BIN_EDGES[band]
        last_bin = BIN_EDGES[band + 1]
        gain = BAND_GAIN_Q8[band]

        for k in range(first_bin, last_bin):
            scaled_real = (real[k] * gain) >> 8
            scaled_imag = (imag[k] * gain) >> 8
            power = scaled_real * scaled_real + scaled_imag * scaled_imag

            if power > peak_power:
                peak_power = power

        target = power_to_level(peak_power)
        old = previous[band]

        # Fast attack (7/8) and slower decay (1/8).
        if target > old:
            value = (old + 7 * target + 4) >> 3
        else:
            value = (7 * old + target + 4) >> 3

        levels[band] = value

    return levels


def make_matrix(levels):
    """Map each band to eight yellow LEDs with brightness 0..255."""
    matrix = np.zeros((8, 8), dtype=np.uint8)

    for col in range(8):
        height = levels[col]

        for row in range(8):
            brightness = height - (row << 8)

            if brightness < 0:
                brightness = 0
            elif brightness > 255:
                brightness = 255

            matrix[row, col] = brightness

    return matrix


# ============================================================
# LIVE VISUALIZATION (PYTHON ONLY)
# ============================================================

def main():
    previous = [0] * 8

    fig, ax = plt.subplots()
    yellow = LinearSegmentedColormap.from_list(
        'yellow',
        ['black', '#ffff00']
    )

    initial_matrix = np.zeros((8, 8), dtype=np.uint8)
    img = ax.imshow(
        initial_matrix,
        origin='lower',
        cmap=yellow,
        vmin=0,
        vmax=255,
        interpolation='nearest'
    )

    ax.set_xticks(range(8))
    ax.set_yticks(range(8))
    ax.set_xlabel('Frequency band')
    ax.set_ylabel('LED row')
    ax.set_title('Integer FFT / 8-band LED matrix')

    with sd.InputStream(
        samplerate=FS,
        channels=1,
        blocksize=N,
        dtype='int16'
    ) as stream:

        def update(frame):
            nonlocal previous

            samples, overflowed = stream.read(N)

            if overflowed:
                print('Audio overflow')

            mono_samples = samples[:, 0]
            previous = process(mono_samples, previous)
            matrix = make_matrix(previous)
            img.set_data(matrix)

            return (img,)

        animation = FuncAnimation(
            fig,
            update,
            interval=30,
            blit=True,
            cache_frame_data=False
        )

        plt.show()


if __name__ == '__main__':
    main()
