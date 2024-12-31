import processing.serial.*;

Serial mySerial;
PrintWriter output;
int lastRecordedHour = -1;
int lastRecordedMinute = -1;

// Variáveis para o gráfico
float[][] values;
int index = 0;
float minValue = Float.MAX_VALUE;
float maxValue = Float.MIN_VALUE;

// Variáveis para controle de conexão
boolean isConnected = false;
long lastDataTime = 0;
final long TIMEOUT = 3000; // 3 segundos de timeout

// Variáveis para informações adicionais
float currentVoltage = 0, currentSmoothed = 0, currentFiltered = 0, currentLowPass = 0, currentHighPass = 0;
double totalValue = 0; // Mudado para double para maior precisão
long sampleCount = 0;
boolean hasReceivedData = false;

// Variáveis para depuração
PrintWriter debugLog;

// Tamanhos de fonte
int titleFontSize = 24;
int labelFontSize = 16;
int valueFontSize = 14;

// Margens
int leftMargin = 80;
int rightMargin = 50;
int topMargin = 50;
int bottomMargin = 100;

// Variáveis para controle de visualização
boolean[] showSignal = {true, true, true, true, true}; // Controles para cada sinal
String[] signalNames = {"Valor Bruto", "Suavizado", "Filtrado (Notch)", "Filtrado (Passa-baixa)", "Filtrado (Passa-alta)"};
color[] signalColors = {color(0, 0, 128), color(255, 0, 0), color(0, 128, 0), color(128, 0, 128), color(128, 0, 0)}; // Cores diferentes para cada sinal

// Variáveis para checkboxes
int checkboxSize = 15;
int checkboxY = 60;
int checkboxSpacing = 200;

void setup() {
  size(1360, 768);
  setupFonts();
  
  // Inicializa o arquivo de log de depuração
  debugLog = createWriter("debug_log.txt");
  
  // Tenta conectar à porta serial
  try {
    String portName = Serial.list()[0];
    mySerial = new Serial(this, portName, 115200); //ESP32 Wroom-32: 115200 e ARDUINO UNO: 9600
    isConnected = true;
    createNewFile();
  } catch (Exception e) {
    println("Erro ao conectar à porta serial: " + e.getMessage());
    debugLog.println("Erro ao conectar à porta serial: " + e.getMessage());
    debugLog.flush();
  }
  
  values = new float[5][width - leftMargin - rightMargin];  // Armazena 5 variáveis
  for (int i = 0; i < values[0].length; i++) {
    for (int j = 0; j < 5; j++) {
      values[j][i] = 0;
    }
  }
}

void setupFonts() {
  PFont titleFont = createFont("Arial", titleFontSize, true);
  PFont labelFont = createFont("Arial", labelFontSize, true);
  PFont valueFont = createFont("Arial", valueFontSize, true);
  
  textFont(titleFont);
}

void draw() {
  background(240);
  
  if (isConnected) {
    checkConnection();
    readSerial();
  }
  
  drawGraph();
  drawLegend();
  drawCheckboxes();
  drawAdditionalInfo();
}

void checkConnection() {
  if (millis() - lastDataTime > TIMEOUT) {
    isConnected = false;
    println("Conexão perdida");
  }
}

void readSerial() {
  int currentHour = hour();
  int currentMinute = minute();
  
  if ((currentHour != lastRecordedHour) || (currentMinute / 30 != lastRecordedMinute / 30)) {
    if (output != null) {
      output.flush();
      output.close();
    }
    createNewFile();
    lastRecordedHour = currentHour;
    lastRecordedMinute = currentMinute;
  }
  
  while (mySerial.available() > 0) {
    String value = mySerial.readStringUntil('\n');
    if (value != null) {
      value = value.trim();
      String[] splitValues = split(value, ','); // Divide em partes
      
      if (splitValues.length == 5) {  // Verifica se tem os 5 valores
        float voltage = float(splitValues[0]);
        float smoothedVoltage = float(splitValues[1]);
        float filteredVoltage = float(splitValues[2]);
        float lowPassFilteredVoltage = float(splitValues[3]);
        float highPassFilteredVoltage = float(splitValues[4]);
        
        recordData(voltage, smoothedVoltage, filteredVoltage, lowPassFilteredVoltage, highPassFilteredVoltage);
        updateValues(voltage, smoothedVoltage, filteredVoltage, lowPassFilteredVoltage, highPassFilteredVoltage);
        lastDataTime = millis();
      } else {
        println("Valor inválido recebido: " + value);
        debugLog.println("Valor inválido recebido: " + value);
        debugLog.flush();
      }
    }
  }
}

void updateValues(float voltage, float smoothed, float filtered, float lowPass, float highPass) {
  values[0][index] = voltage;        // Já está em mV
  values[1][index] = smoothed;       // Já está em mV
  values[2][index] = filtered;       // Já está em mV
  values[3][index] = lowPass;        // Já está em mV
  values[4][index] = highPass;        // Já está em mV
  index = (index + 1) % values[0].length;

  currentVoltage = voltage;
  currentSmoothed = smoothed;
  currentFiltered = filtered;
  currentLowPass = lowPass;
  currentHighPass = highPass;
  
  recalculateMinMax();
  
  // Atualiza a média
  sampleCount++;
  totalValue += voltage;
  hasReceivedData = true;
}


void drawGraph() {
  stroke(0);
  // Desenha eixo Y
  line(leftMargin, topMargin, leftMargin, height - bottomMargin);
  // Desenha eixo X
  line(leftMargin, height - bottomMargin, width - rightMargin, height - bottomMargin);
  
  // Desenha cada sinal se estiver ativado
  for (int signalIndex = 0; signalIndex < 5; signalIndex++) {
    if (showSignal[signalIndex]) {
      stroke(signalColors[signalIndex]);
      noFill();
      beginShape();
      for (int i = 0; i < values[0].length; i++) {
        int xi = (index - i + values[0].length) % values[0].length;
        float x = map(i, 0, values[0].length - 1, width - rightMargin, leftMargin);
        
        // Adiciona verificação de segurança para o valor Y
        float value = values[signalIndex][xi];
        float y;
        if (value < minValue) y = height - bottomMargin;
        else if (value > maxValue) y = topMargin;
        else y = map(value, minValue, maxValue, height - bottomMargin - 10, topMargin + 10);
        
        vertex(x, y);
      }
      endShape();
    }
  }
}

// Adicione uma nova variável para o deslocamento horizontal dos checkboxes
int checkboxStartX = leftMargin + 100; // Ajuste este valor conforme necessário

// Checkboxes
void drawCheckboxes() {
  textFont(createFont("Arial", labelFontSize, true));
  for (int i = 0; i < 5; i++) {
    int x = checkboxStartX + (i * checkboxSpacing);
    
    // Desenha a caixa
    stroke(0);
    fill(255);
    rect(x, checkboxY, checkboxSize, checkboxSize);
    
    // Desenha o X se estiver selecionado
    if (showSignal[i]) {
      stroke(signalColors[i]);
      line(x, checkboxY, x + checkboxSize, checkboxY + checkboxSize);
      line(x + checkboxSize, checkboxY, x, checkboxY + checkboxSize);
    }
    
    // Desenha o texto
    fill(0);
    textAlign(LEFT, CENTER);
    text(signalNames[i], x + checkboxSize + 5, checkboxY + checkboxSize/2);
  }
}

void mousePressed() {
  // Verifica se clicou em alguma checkbox
  for (int i = 0; i < 5; i++) {
    int x = checkboxStartX + (i * checkboxSpacing);
    if (mouseX >= x && mouseX <= x + checkboxSize && 
        mouseY >= checkboxY && mouseY <= checkboxY + checkboxSize) {
      showSignal[i] = !showSignal[i];
      recalculateMinMax();
      break;
    }
  }
}
void recalculateMinMax() {
  minValue = Float.MAX_VALUE;
  maxValue = Float.MIN_VALUE;
  
  boolean foundValidValue = false;
  
  // Encontra min e max reais
  for (int i = 0; i < 5; i++) {
    if (showSignal[i]) {
      for (int j = 0; j < values[i].length; j++) {
        if (values[i][j] != 0) {  // Ignora valores zero
          minValue = min(minValue, values[i][j]);
          maxValue = max(maxValue, values[i][j]);
          foundValidValue = true;
        }
      }
    }
  }
  
  // Se não encontrou valores válidos ou min == max
  if (!foundValidValue || minValue == maxValue) {
    // Define valores padrão
    minValue = -1;
    maxValue = 1;
  } else {
    // Adiciona uma margem de 10% acima e abaixo
    float range = maxValue - minValue;
    minValue -= range * 0.1;
    maxValue += range * 0.1;
  }
  
  // Garante uma diferença mínima
  if (abs(maxValue - minValue) < 0.001) {
    maxValue = minValue + 0.001;
  }
}

void drawLegend() {
  textFont(createFont("Arial", labelFontSize, true));
  fill(0);
  textAlign(CENTER, CENTER);
  pushMatrix();
  translate(30, height / 2);
  rotate(-HALF_PI);
  text("Tensão (mV)", 0, 0);
  popMatrix();
  
  textAlign(CENTER, BOTTOM);
  text("Tempo", width / 2, height - 60);
  
  textFont(createFont("Arial", valueFontSize, true));
  textAlign(RIGHT, TOP);
  text(nf(maxValue, 0, 1) + " mV", leftMargin - 5, topMargin + 10);
  textAlign(RIGHT, BOTTOM);
  text(nf(minValue, 0, 1) + " mV", leftMargin - 5, height - bottomMargin - 10);
  
  textFont(createFont("Arial", titleFontSize, true));
  if (isConnected) {
    fill(0, 128, 0);
    text("Conectado", width - 100, 30);
  } else {
    fill(128, 0, 0);
    text("Desconectado", width - 100, 30);
  }
}

void drawAdditionalInfo() {
  textFont(createFont("Arial", labelFontSize, true));
  fill(0);
  textAlign(LEFT, TOP);
  
  text("Informações Adicionais:", leftMargin, height - 50);
  
  textFont(createFont("Arial", valueFontSize, true));
  text("Valor Atual: " + nf(currentVoltage, 0, 3) + " mV", leftMargin, height - 30);
  text("Suavizado: " + nf(currentSmoothed, 0, 3) + " mV", leftMargin + 200, height - 30);
  text("Filtro Notch: " + nf(currentFiltered, 0, 3) + " mV", leftMargin + 400, height - 30);
  text("Filtro Passa-Baixa: " + nf(currentLowPass, 0, 3) + " mV", leftMargin + 610, height - 30);
  text("Filtro Passa-Alta: " + nf(currentHighPass, 0, 3) + " mV", leftMargin + 860, height - 30);
  text("Amostras: " + sampleCount, width - 200, height - 30);
  
  //String avgText = "N/A";
  //if (hasReceivedData && sampleCount > 0) {
    //double averageValue = totalValue / sampleCount;
    //avgText = nf((float)averageValue, 0, 1) + " mV";
  //}
  //text("Média: " + avgText, width - 200, height - 30);
  
}

void createNewFile() {
  String fileName = "dados_" + nf(day(), 2) + "-" + nf(month(), 2) + "-" + year() + "_" + nf(hour(), 2) + "-" + nf(minute(), 2) + "-" + nf(second(), 2) + ".csv";
  output = createWriter(fileName);
  output.println("h:m:s:ms; Valor Bruto; Suavizado; Filtro Notch; Filtro Passa-Baixa; Filtro Passa-Alta");
}

void recordData(float voltage, float smoothedVoltage, float filteredVoltage, float lowPassFilteredVoltage, float highPassFilteredVoltage) {
  String timeStamp = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2) + ":" + nf(millis() % 1000, 3);
  
  // Formata os valores (já em mV)
  String voltageStr = nf(voltage, 0, 5).replace('.', ',');
  String smoothedVoltageStr = nf(smoothedVoltage, 0, 5).replace('.', ',');
  String filteredVoltageStr = nf(filteredVoltage, 0, 5).replace('.', ',');
  String lowPassFilteredVoltageStr = nf(lowPassFilteredVoltage, 0, 5).replace('.', ',');
  String highPassFilteredVoltageStr = nf(highPassFilteredVoltage, 0, 5).replace('.', ',');
  
  output.println(timeStamp + ";" + voltageStr + ";" + smoothedVoltageStr + ";" + filteredVoltageStr + ";" + lowPassFilteredVoltageStr + ";" + highPassFilteredVoltageStr);
  output.flush();
}
