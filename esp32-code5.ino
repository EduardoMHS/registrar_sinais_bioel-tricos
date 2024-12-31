#include <Wire.h>
#include <Adafruit_ADS1X15.h>

Adafruit_ADS1115 ads;

const int WINDOW_SIZE = 20;
float readings[WINDOW_SIZE]; // Usando float para suavização melhorada
uint8_t readIndex = 0;
float total = 0;

const float notchFrequency = 60.0;
const float sampleRate = 2000.0;  // Atualizado para 2kHz

// Coeficientes do filtro Notch
float b0, b1, b2, a0, a1, a2;
float x1 = 0, x2 = 0, y1_filter = 0, y2 = 0;

const float lowPassCutoff = 10.0;
float lowPassRC = 1.0 / (2 * PI * lowPassCutoff);
float lowPassAlpha;
float prevLowPassFiltered = 0;

const float highPassCutoff = 1.0;
float highPassRC = 1.0 / (2 * PI * highPassCutoff);
float highPassAlpha;
float prevHighPassFiltered = 0;
float prevInput = 0;

// Novos fatores de correção devido ao divisor de tensão
const float VOLTAGE_DIVIDER_FACTOR = 2.0; // 2,0 se R1 for igual a R2; R1/R1+R2 para R1 diferente de R2
const float SERIES_RESISTOR_FACTOR = 1.0;

unsigned long previousMicros = 0;
const unsigned long interval = 250; // 2kHz taxa de amostragem

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);  // Inicializando o I2C com os pinos corretos

  if (!ads.begin()) {
    Serial.println("Falha ao inicializar o ADS1115!");
    while (1);
  }

  ads.setGain(GAIN_TWOTHIRDS);  // Configura o ganho para +/- 6.144V (maior faixa possível)

  // Inicializando os arrays de leitura
  for (int i = 0; i < WINDOW_SIZE; i++) {
    readings[i] = 0;
  }

  // Cálculo dos coeficientes dos filtros
  calculateFilterCoefficients();

  Serial.println("Voltage,SmoothedVoltage,FilteredVoltage,LowPassFiltered,HighPassFiltered");
}

void loop() {
  unsigned long currentMicros = micros();

  if (currentMicros - previousMicros >= interval) {
    previousMicros = currentMicros;

    // Leitura do ADS1115 (canal 0)
    int16_t adsValue = ads.readADC_SingleEnded(0);
    float adsSmoothed = applyExponentialMovingAverage(adsValue);  // Usando suavização exponencial

    // Ajuste no cálculo da tensão para compensar o divisor de tensão e o resistor em série
    float voltage = adsValue * 0.1875 * VOLTAGE_DIVIDER_FACTOR * SERIES_RESISTOR_FACTOR;
    float smoothedVoltage = adsSmoothed * 0.1875 * VOLTAGE_DIVIDER_FACTOR * SERIES_RESISTOR_FACTOR;

    // Aplicação dos filtros
    float filteredVoltage = applyNotchFilter(voltage);
    float lowPassFilteredVoltage = applyLowPassFilter(filteredVoltage);
    float highPassFilteredVoltage = applyHighPassFilter(lowPassFilteredVoltage);

    // Impressão dos resultados na Serial
    Serial.print(voltage);
    Serial.print(",");
    Serial.print(smoothedVoltage);
    Serial.print(",");
    Serial.print(filteredVoltage);
    Serial.print(",");
    Serial.print(lowPassFilteredVoltage);
    Serial.print(",");
    Serial.println(highPassFilteredVoltage);
  }
}

// Função para calcular os coeficientes do filtro Notch e passa-baixa/alta
void calculateFilterCoefficients() {
  // Cálculo dos coeficientes do filtro Notch usando um filtro IIR
  float Q = 30.0;  // Fator de qualidade ajustado para melhor rejeição de ruído
  float w0 = 2 * PI * notchFrequency / sampleRate;
  float cos_w0 = cos(w0);
  float sin_w0 = sin(w0);
  float alpha = sin_w0 / (2 * Q);

  b0 = 1;
  b1 = -2 * cos_w0;
  b2 = 1;
  a0 = 1 + alpha;
  a1 = -2 * cos_w0;
  a2 = 1 - alpha;

  b0 /= a0;
  b1 /= a0;
  b2 /= a0;
  a1 /= a0;
  a2 /= a0;

  // Coeficientes do filtro passa-baixa
  float dt = 1.0 / sampleRate;
  lowPassAlpha = dt / (lowPassRC + dt);

  // Coeficientes do filtro passa-alta
  highPassAlpha = highPassRC / (highPassRC + dt);
}

// Função para aplicar a suavização exponencial
float applyExponentialMovingAverage(float newValue) {
  const float alpha = 0.1;  // Peso da suavização exponencial (ajuste conforme necessário)
  float output = alpha * newValue + (1.0 - alpha) * total;
  total = output;
  return output;
}

// Função para aplicar o filtro Notch IIR
float applyNotchFilter(float input) {
  float output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1_filter - a2 * y2;
  x2 = x1;
  x1 = input;
  y2 = y1_filter;
  y1_filter = output;
  return output;
}

// Função para aplicar o filtro passa-baixa
float applyLowPassFilter(float input) {
  float output = lowPassAlpha * input + (1.0 - lowPassAlpha) * prevLowPassFiltered;
  prevLowPassFiltered = output;
  return output;
}

// Função para aplicar o filtro passa-alta
float applyHighPassFilter(float input) {
  float output = highPassAlpha * (prevHighPassFiltered + input - prevInput);
  prevHighPassFiltered = output;
  prevInput = input;
  return output;
}
