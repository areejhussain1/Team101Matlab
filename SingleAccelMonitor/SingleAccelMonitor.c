// SingleAccelMonitor.c

#include <stdio.h>
#include <stdint.h>   // uint8_t, uint16_t, uint32_t, int16_t, etc.
#include <stddef.h>   // size_t
#include <stdbool.h>  // bool

#include "pico/stdlib.h"
#include "pico/types.h"    // defines 'uint' used by Pico SDK
#include "hardware/spi.h"
#include "hardware/gpio.h"

// =============================
// Configuration
// =============================

#define SPI_PORT        spi0
#define SPI_BAUD_HZ     8000000   // 8 MHz, ADXL372 supports up to 10 MHz

#define PIN_SPI_SCK     2
#define PIN_SPI_MOSI    3
#define PIN_SPI_MISO    4

// For future expansion, we support multiple sensors
#define NUM_SENSORS     1   // set to 4 later when you add more sensors

// Per-sensor pin assignments (adjust for your wiring)
typedef struct {
    uint cs_pin;          // chip-select pin
    uint int1_pin;        // INT1 pin from ADXL372
    volatile bool fifo_irq;  // set by GPIO interrupt
} adxl372_sensor_t;

// Example for 1 sensor; you can add 3 more entries later.
static adxl372_sensor_t sensors[NUM_SENSORS] = {
    { .cs_pin = 5, .int1_pin = 6, .fifo_irq = false },
    // { .cs_pin = 7,  .int1_pin = 8,  .fifo_irq = false }, // sensor 1
    // { .cs_pin = 9,  .int1_pin = 10, .fifo_irq = false }, // sensor 2
    // { .cs_pin = 11, .int1_pin = 12, .fifo_irq = false }, // sensor 3
};

// =============================
// ADXL372 register map (subset)
// =============================

// IDs
#define ADXL372_REG_DEVID_AD        0x00
#define ADXL372_REG_DEVID_MST       0x01
#define ADXL372_REG_PARTID          0x02
#define ADXL372_REG_REVID           0x03

#define ADXL372_REG_STATUS          0x04
#define ADXL372_REG_FIFO_ENTRIES    0x07

#define ADXL372_REG_FIFO_SAMPLES    0x39
#define ADXL372_REG_FIFO_CTL        0x3A
#define ADXL372_REG_INT1_MAP        0x3B
#define ADXL372_REG_TIMING          0x3D
#define ADXL372_REG_MEASURE         0x3E
#define ADXL372_REG_POWER_CTL       0x3F
#define ADXL372_REG_RESET           0x41
#define ADXL372_REG_FIFO_DATA       0x42

// Expected ID values from datasheet
#define ADXL372_DEVID_AD_VALUE      0xAD
#define ADXL372_DEVID_MST_VALUE     0x1D
#define ADXL372_PARTID_VALUE        0xFA

// FIFO & interrupt configuration
#define ADXL372_FIFO_WATERMARK      240  // number of FIFO *samples* (not XYZ sets)
// With XYZ in FIFO, 240 samples ≈ 80 full XYZ sets

// =============================
// Low-level SPI helpers
// =============================

// Command byte: A6..A0, RW in bit0 (1 = read, 0 = write)
static inline void adxl372_write_bytes(uint cs_pin, uint8_t reg, const uint8_t *data, size_t len) {
    uint8_t cmd = (uint8_t)((reg << 1) & 0xFE); // RW=0
    gpio_put(cs_pin, 0);
    spi_write_blocking(SPI_PORT, &cmd, 1);
    spi_write_blocking(SPI_PORT, data, len);
    gpio_put(cs_pin, 1);
}

static inline void adxl372_write_reg(uint cs_pin, uint8_t reg, uint8_t value) {
    adxl372_write_bytes(cs_pin, reg, &value, 1);
}

static inline void adxl372_read_bytes(uint cs_pin, uint8_t reg, uint8_t *data, size_t len) {
    uint8_t cmd = (uint8_t)((reg << 1) | 0x01); // RW=1
    gpio_put(cs_pin, 0);
    spi_write_blocking(SPI_PORT, &cmd, 1);
    spi_read_blocking(SPI_PORT, 0x00, data, len);
    gpio_put(cs_pin, 1);
}

static inline uint8_t adxl372_read_reg(uint cs_pin, uint8_t reg) {
    uint8_t val = 0;
    adxl372_read_bytes(cs_pin, reg, &val, 1);
    return val;
}

// =============================
// ADXL372 setup
// =============================

static bool adxl372_init_sensor(adxl372_sensor_t *s) {
    // Reset the device
    uint8_t reset_cmd = 0x52;
    adxl372_write_reg(s->cs_pin, ADXL372_REG_RESET, reset_cmd);
    sleep_ms(5);

    // Check IDs
    uint8_t devid_ad  = adxl372_read_reg(s->cs_pin, ADXL372_REG_DEVID_AD);
    uint8_t devid_mst = adxl372_read_reg(s->cs_pin, ADXL372_REG_DEVID_MST);
    uint8_t partid    = adxl372_read_reg(s->cs_pin, ADXL372_REG_PARTID);

    if (devid_ad != ADXL372_DEVID_AD_VALUE ||
        devid_mst != ADXL372_DEVID_MST_VALUE ||
        partid != ADXL372_PARTID_VALUE) {
        // ID mismatch – check wiring / power / SPI mode
        return false;
    }

    // Put into standby mode (POWER_CTL MODE = 00)
    adxl372_write_reg(s->cs_pin, ADXL372_REG_POWER_CTL, 0x00);

    // Set ODR to 6400 Hz (TIMING ODR bits [7:5] = 100)
    //uint8_t timing = (uint8_t)(1u << 5); // ODR = 800 Hz, rest = 0
    uint8_t timing = (uint8_t)(4u << 5); // ODR = 6400 Hz, rest = 0

    adxl372_write_reg(s->cs_pin, ADXL372_REG_TIMING, timing);

    // MEASURE: set bandwidth (BANDWIDTH[2:0] = 100 => 3200 Hz), low_noise=1 (optional)
    uint8_t measure = 0;
    measure |= (1u << 3); // LOW_NOISE = 1
    measure |= 4u;        // BANDWIDTH = 100 (3200 Hz)
    adxl372_write_reg(s->cs_pin, ADXL372_REG_MEASURE, measure);

    // FIFO watermark samples (0..512). We keep it <=255 so MSB in FIFO_CTL stays 0.
    adxl372_write_reg(s->cs_pin, ADXL372_REG_FIFO_SAMPLES, ADXL372_FIFO_WATERMARK);

    // FIFO_CTL:
    //   FIFO_FORMAT = 000 (XYZ)
    //   FIFO_MODE   = 01 (stream)
    //   FIFO_SAMPLES[8] = 0 (we only use 0..255)
    // Bits: [5:3] format, [2:1] mode, [0] MSB of FIFO_SAMPLES
    uint8_t fifo_ctl = 0;
    fifo_ctl |= (1u << 1); // FIFO_MODE = 01 (stream)
    adxl372_write_reg(s->cs_pin, ADXL372_REG_FIFO_CTL, fifo_ctl);

    // INT1_MAP:
    // Map FIFO_FULL and FIFO_OVR to INT1 (active-high)
    // bit 3 = FIFO_OVR_INT1, bit 2 = FIFO_FULL_INT1
    uint8_t int1_map = (uint8_t)((1u << 3) | (1u << 2));
    adxl372_write_reg(s->cs_pin, ADXL372_REG_INT1_MAP, int1_map);

    // Clear any pending interrupts
    (void)adxl372_read_reg(s->cs_pin, ADXL372_REG_STATUS);

    // POWER_CTL:
    //   FILTER_SETTLE = 1 (16 ms)
    //   MODE = 11 (full bandwidth measurement)
    uint8_t power_ctl = 0;
    power_ctl |= (1u << 4); // FILTER_SETTLE = 1
    power_ctl |= 0x03;      // MODE = 11
    adxl372_write_reg(s->cs_pin, ADXL372_REG_POWER_CTL, power_ctl);

    sleep_ms(20); // let filters settle

    return true;
}

// =============================
// GPIO interrupt handler
// =============================

void gpio_int_callback(uint gpio, uint32_t events) {
    (void)events;
    for (int i = 0; i < NUM_SENSORS; i++) {
        if (gpio == sensors[i].int1_pin) {
            sensors[i].fifo_irq = true;
        }
    }
}

// =============================
// FIFO read & CSV output
// =============================

typedef struct {
    int16_t x;
    int16_t y;
    int16_t z;
} adxl_xyz_sample_t;

// Parse and read FIFO for one sensor when the watermark interrupt fired
static void adxl372_service_fifo(adxl372_sensor_t *s, int sensor_index) {
    // Check how many FIFO samples are available (0..512).
    // We only read LSB here because our watermark is <=255.
    uint8_t entries_lsb = adxl372_read_reg(s->cs_pin, ADXL372_REG_FIFO_ENTRIES);
    uint16_t entries = entries_lsb;

    if (entries == 0) {
        // No data; nothing to do
        return;
    }

    // Each "entry" is one axis sample (16-bit word) in FIFO.
    // We're storing XYZ, so each full sample set is 3 entries.
    uint16_t sets = entries / 3;
    if (sets == 0) {
        return;
    }

    // Per datasheet, leave at least 1 set in FIFO to keep alignment stable
    // (for 3-axis, max 169 sets per read).
    if (sets > 169) sets = 169;
    if (sets > 1) {
        sets -= 1;
    } else {
        // only 1 set; leave it there and come back later
        return;
    }

    uint16_t words_to_read = (uint16_t)(sets * 3);  // number of axis entries (X/Y/Z)
    uint16_t bytes_to_read = (uint16_t)(words_to_read * 2);

    // Buffer for raw FIFO bytes
    uint8_t buf[1024];
    if (bytes_to_read > sizeof(buf)) {
        bytes_to_read = sizeof(buf);
        words_to_read = (uint16_t)(bytes_to_read / 2);
        sets = (uint16_t)(words_to_read / 3);
    }

    // Read all the FIFO words we decided on.
    // FIFO_DATA (0x42): multibyte read pops continuous words from FIFO.
    uint8_t cmd = (uint8_t)((ADXL372_REG_FIFO_DATA << 1) | 0x01);
    gpio_put(s->cs_pin, 0);
    spi_write_blocking(SPI_PORT, &cmd, 1);
    spi_read_blocking(SPI_PORT, 0x00, buf, bytes_to_read);
    gpio_put(s->cs_pin, 1);

    // Decode FIFO words into XYZ samples.
    // FIFO data format: 16-bit word, acceleration is in bits [15:4],
    // twos complement, left-justified. Bit 0 is "series start" indicator.
    uint32_t now = time_us_32();
    int axis_index = 0;  // 0 = X, 1 = Y, 2 = Z
    adxl_xyz_sample_t current = {0};

    for (uint16_t i = 0; i < words_to_read; i++) {
        uint8_t hi = buf[2 * i];
        uint8_t lo = buf[2 * i + 1];

        uint16_t word = (uint16_t)(((uint16_t)hi << 8) | lo);
        bool series_start = (word & 0x0001u) != 0;

        // Sign-extend 12-bit left-justified value (bits 15..4) into 16-bit
        int16_t sample = (int16_t)word;
        sample >>= 4; // arithmetic shift keeps sign

        if (series_start) {
            // Start of a new XYZ series; re-align to X
            axis_index = 0;
        }

        if (axis_index == 0) {
            current.x = sample;
        } else if (axis_index == 1) {
            current.y = sample;
        } else if (axis_index == 2) {
            current.z = sample;

            // We have a complete XYZ sample – print CSV
            // Format: timestamp_us,sensor_id,x_raw,y_raw,z_raw
            printf("%lu,%d,%d,%d,%d\n",
                   (unsigned long)now,
                   sensor_index,
                   (int)current.x,
                   (int)current.y,
                   (int)current.z);
        }

        axis_index = (axis_index + 1) % 3;
    }

    // Read STATUS to clear FIFO_FULL / FIFO_OVR interrupt flags.
    (void)adxl372_read_reg(s->cs_pin, ADXL372_REG_STATUS);
}

// =============================
// Main
// =============================

int main() {
    stdio_init_all();

    sleep_ms(2000);
    while (!stdio_usb_connected()) {
        sleep_ms(100);
    }
    printf("SingleAccelMonitor starting...\n");

    // Init SPI
    spi_init(SPI_PORT, SPI_BAUD_HZ);
    gpio_set_function(PIN_SPI_SCK,  GPIO_FUNC_SPI);
    gpio_set_function(PIN_SPI_MOSI, GPIO_FUNC_SPI);
    gpio_set_function(PIN_SPI_MISO, GPIO_FUNC_SPI);

    // Init sensor CS and INT pins
    for (int i = 0; i < NUM_SENSORS; i++) {
        gpio_init(sensors[i].cs_pin);
        gpio_set_dir(sensors[i].cs_pin, GPIO_OUT);
        gpio_put(sensors[i].cs_pin, 1); // CS idle high

        gpio_init(sensors[i].int1_pin);
        gpio_set_dir(sensors[i].int1_pin, GPIO_IN);
        gpio_pull_down(sensors[i].int1_pin); // or pull-up, depending on board
    }

    // Set up GPIO interrupt callback (rising edge on INT1 of sensor 0)
    gpio_set_irq_enabled_with_callback(
        sensors[0].int1_pin,
        GPIO_IRQ_EDGE_RISE,
        true,
        &gpio_int_callback
    );
    // For extra sensors, you only need to enable IRQs:
    // for (int i = 1; i < NUM_SENSORS; i++) {
    //     gpio_set_irq_enabled(sensors[i].int1_pin, GPIO_IRQ_EDGE_RISE, true);
    // }

    // Initialize all sensors
    for (int i = 0; i < NUM_SENSORS; i++) {
        bool ok = adxl372_init_sensor(&sensors[i]);
        if (!ok) {
            printf("Sensor %d init FAILED (check wiring / power)\n", i);
        } else {
            printf("Sensor %d init OK\n", i);
        }
    }

    printf("timestamp_us,sensor_id,x_raw,y_raw,z_raw\n");

    // Main loop: respond to FIFO interrupts
    while (true) {
        for (int i = 0; i < NUM_SENSORS; i++) {
            if (sensors[i].fifo_irq) {
                sensors[i].fifo_irq = false;
                adxl372_service_fifo(&sensors[i], i);
            }
        }

        tight_loop_contents();
    }

    
    return 0;
}
