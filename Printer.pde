//Printer
//A tab to controll your local 3D printer through the Doodle3D WiFi-Box

//IMPORTANT//----------

//It is important that you declare the printer class in your processing sketch
//An example of how to declare the printer class is: Printer printer = new Printer("10.0.0.188");
//Note that you need to add the IP adress of your WiFi-Box

//Make sure you start the printer correctly by typing printer.startUp(); in the setup()
//Wait patiently before the printer is 'homed' before sending any codes

//Make sure you type printer.update(); in your void draw();
//Please note that you can NOT print in your void setup(); in this example

//-----------

//To print, type printer.printLine(x,y,x,y,z); just like the line(); function but with an additional Z axis. The printer will use your sketch size(); as borders for the printer
//It is adviced to start your print with a print.cleanNozzle();, this will make an start printline
//This will cleaning your nozzle and makes sure you can print filament

//To cancel a print or simply to return the printhead home use the printer.returnHome(); function

//FUNCTIONS:
/*
NEEDED:
startUp() //Will make your printer start ready. You add startUp() in your setup()
update() //Is needed to buffer the print that is send. You add update() in your draw()
OPTIONAL:
returnHome() //Stop the current print and will return to the homing position
cleanNozzle() //Draw an line along the left side of your printer to clean the nozzle and wont lift up and retract filament after, which makes it a nice way to start a print
startStopFan() //Turn the fan on when it is off and will turn it of when it is on
myTranslate() //place a new x and y position to start from
moveTo() //places a new start position to start the next line from
lineTo() //place a new end position to end the next line from
receiveConfigAll() //define and print the dimensions of the printer
printlnReceivedConfig() //only print the dimensions of the printer
*/

public class Printer {

  //Dimensions of your printer
  int printer_x; //in mm Printable dimension X
  int printer_y; //in mm Printable dimension Y
  int printer_z; //in mm Printable dimension Z
  int feedrate = 1000; //Feedrate in 1000mm per minute
  float filamentThickness; //mm Thickness of the filement
  float layerHeight; //mm Thickness of the line you want to print
  float nozzleWidth = 1.4;
  float amount_of_filament = 150; //amount of filament in percents %

  //Post adresses where the WiFi-Box can post to
  PostRequest stop;
  PostRequest post;
  PostRequest config;
  PostRequest heatup;

  //creates a JSONObject to get results from the WiFi-Box
  JSONObject json;
  JSONObject info_status;

  //calculation result for the amount of filement used in a single line
  float filament_calculation = 2;

  //turn on/off fan
  boolean fanTurning = true;

  //Gcode buffer, gets filled and released after a couple of seconds.
  String gcode_buffer = "";
  int gcode_buffer_seconds = 0;

  boolean cleanNozzle_state = false;
  float current_Zaxis = 0;

  float prevgcodeX, prevgcodeY;
  float startgcodeX, startgcodeY;
  float gcodeX, gcodeY;
  float printZconstrain;
  float moveX=0, moveY=0, moveZ=0;
  float translateX=0, translateY=0;

  StringList bufferList;
  StringList bufferList500;

  String boxIP;
  Printer(String ip) {
    boxIP = ip;
    //Post adresses where the WiFi-Box can post to
    stop = new PostRequest("http://"+boxIP+"/d3dapi/printer/stop");
    post = new PostRequest("http://"+boxIP+"/d3dapi/printer/print");
    config = new PostRequest("http://"+boxIP+"/d3dapi/config");
    heatup = new PostRequest("http://"+boxIP+"/d3dapi/printer/heatup");
    bufferList = new StringList();
    bufferList500 = new StringList();
  }

  //This void must be writen in the void draw(), it is needed to time the amount of data being send to the printer.
  void update() {
    //Uses your PC's clock seconds as a buffer for gcode
    gcode_buffer_seconds = second();

    //Creates a buffer to prefent to many gcodes being send at the same time.
//    if (gcode_buffer_seconds % 2 == 0) { //Remove this if()-statement to make the printer interactive BUT notice that it cannot post to many codes at the same time.
      if (bufferList.size() > 0 || bufferList500.size() > 0) {
        printerReady();
      }
  }

  void returnHome() {
    //stop.addData("gcode", json.getString("printer.endcode"));
    stop.addData("gcode", "G28 X0.0 Y0.0 Z0.0 \n G1 "+(filament_calculation-5)+" -5.0 F"+feedrate+"\n M107");
    stop.addData("start", "true");
    stop.send();
    bufferList.clear();
    bufferList500.clear();
    gcode_buffer = "";
  }

  //Will give the printer a basic start up before going
  void startUp() {
    receiveConfigAll();
    heatup.send();
    //post.addData("gcode", json.getString("printer.startcode"));
    fanTurning = false;
//    post.addData("gcode", "G28 X0.0 Y0.0 Z0.0 \n G92 E0\n G1 E 5\n G92 E0\n M107"); //line 1: Homing, line 2: defines current filament as 0, line 3: stops the fan from turning if does
    post.addData("gcode", "G28 X0.0 Y0.0 \n G92 Z0 E0\n G1 E 5\n G92 E0\n M107\n M104 S220"); //line 1: Homing, line 2: defines current filament as 0, line 3: stops the fan from turning if does
    post.addData("start", "true");
    post.send();
    bufferList.clear();
    bufferList500.clear();
    gcode_buffer = "";
  }

  //Makes a printsampel. Can be used to make sure the printer has a clean nozzle and prints filament.
  void cleanNozzle() {
    cleanNozzle_state = true;
    printLine(0, 0, 0, width/2, 1);
    printLine(1, width/2, 1, 0, 1);
  }

  //Makes the Printer follow the line draw
  //Generating the Gcode for a single line, inclusive the calculations needed for the line.
  void printLine(float printX, float printY, float printX2, float printY2, float printZ) {

    lineCalculations(printX, printY, printX2, printY2, printZ);

    currentZaxis();

    //Creates a line in the processing screen to show how the print will look like.
    stroke(255, map(printZ, 0, printer_z/layerHeight, 255, 0));//makes lines further off in the Z-axis darker.
    line(printX, printY, printX2, printY2);//draws a line in the screen.

    gcodeString();
  }

  void receiveConfigAll() {
    //Directs the JSONObject to config/all to get the printer settings
    json = loadJSONObject("http://"+boxIP+"/d3dapi/config/all");
    json = json.getJSONObject("data");

    //Basic printer settings received from the WiFi-Box
    layerHeight = json.getFloat("printer.layerHeight");
    filamentThickness = json.getFloat("printer.filamentThickness");
    printer_x = json.getInt("printer.dimensions.x");
    printer_y = json.getInt("printer.dimensions.y");
    printer_z = json.getInt("printer.dimensions.z");

    printlnReceivedConfig();
  }

  void printlnReceivedConfig() {
    println("Printer type selected: "+json.getString("printer.type"));
    println("layer height is: "+layerHeight);
    println("filamentThickness is: "+filamentThickness);
    println("Printer X: "+printer_x+" Printer Y: "+printer_y+" Printer Z: "+printer_z);
  }
  void startStopFan() {
    if (fanTurning == true) {
      fanTurning = false;
      post.addData("gcode", "M107");
      post.addData("start", "true");
      post.send();
    }
    else {
      fanTurning = true;
      post.addData("gcode", "M106");
      post.addData("start", "true");
      post.send();
    }
  }
  void printGcode() {
    //release the remaining buffer
    for (int i= 0; i<bufferList500.size();i++) {
      gcode_buffer += bufferList500.get(i);
    }
    bufferList.append(gcode_buffer);

    for (int i = 0; i < bufferList.size(); i++) {
      post.addData("gcode", bufferList.get(i));
      println(bufferList.get(i));
      if (i == bufferList.size()-1) {
        post.addData("start", "true");
      }
      post.send();
    }
    //Posts gcode for the printer to print
    if (cleanNozzle_state == false) {
//      post.addData("gcode", "G1 Z"+(current_Zaxis+10)+" E"+(filament_calculation-5)+" F"+feedrate);
      post.addData("gcode", "G1 Z"+(current_Zaxis)+" E"+(filament_calculation)+" F"+feedrate);
      post.send();
    }
    else {
      cleanNozzle_state = false;
    }
    bufferList.clear();
    bufferList500.clear();
    gcode_buffer = "";
  }

  void printerReady() {
    //Get data from the printer, needed to see if the printer is hot enough
    info_status = loadJSONObject("http://"+boxIP+"/d3dapi/info/status");
    info_status = info_status.getJSONObject("data");

    if (info_status.getString("state").equals("disconnected") == false) {

      /*if (info_status.getInt("hotend")+2 > info_status.getInt("hotend_target")) { //checks if the printer is hot enough.
        //!!! If JSONObject["hotend"] or ["hotend_target"] is not found, the chance is high that you printer isn't on or connected.
        println("hot enough!");

        printGcode();
      }
      else {
        println("Temperature is: "+info_status.getInt("hotend")+" Target temperature is: "+info_status.getInt("hotend_target")+"heating up... ");
      }*/
      printGcode();
    }
    else {
      println("Printer is not found, either it is off or it is not connected");
    }
  }

  void gcodeString() {

    String retractFilamentGcode = "G1 Z"+abs(layerHeight*printZconstrain)+" E"+(filament_calculation-5)+" F"+feedrate+"\n";
    //String moveToGcode = "G1 X"+startgcodeX+"Y"+startgcodeY+" Z"+(current_Zaxis+10)+" F"+feedrate+"\n";
    String moveToGcode = "G1 X"+startgcodeX+"Y"+startgcodeY+" F"+feedrate+"\n";
    String returnFilamentGcode = "G1 Z"+abs(layerHeight*printZconstrain)+" E"+(filament_calculation)+"\n";

    //Gcode for the printer
    String moveGcode = retractFilamentGcode + moveToGcode + returnFilamentGcode; //First the printer head has to move to the starting location of the print
    String printGcode = "G1 X"+gcodeX+" Y"+gcodeY+" Z"+abs(layerHeight*printZconstrain)+" E"+(filament_calculation)+" F"+feedrate+"\n"; //Prints the line drawn

    if (bufferList500.size() > 450) {
      for (int i= 0; i<bufferList500.size();i++) {
        gcode_buffer += bufferList500.get(i);
      }
      bufferList.append(gcode_buffer);
      gcode_buffer = "";
      bufferList500.clear();
    }
    //Decides wether or not the printer should retract filament and move upwards
    if (dist(prevgcodeX, prevgcodeY, startgcodeX, startgcodeY)>1) {
      //gcode_buffer += moveGcode+" \n"+printGcode+" \n"; //adds the gcode to a buffer, ready to get released;
      //bufferList500.append(retractFilamentGcode);
      //bufferList500.append(moveToGcode);
      //bufferList500.append(returnFilamentGcode);
      bufferList500.append(printGcode);
    }
    else {
      //gcode_buffer += printGcode+" \n"; //adds the gcode to a buffer, ready to get released;
      bufferList500.append(printGcode);
    }

    prevgcodeX = gcodeX;
    prevgcodeY = gcodeY;
  }

  void lineCalculations(float printX, float printY, float printX2, float printY2, float printZ) {
    startgcodeX = constrain(map(printX, 0, width, 0, printer_x), 0, printer_x);
    startgcodeY = constrain(map(printY, height, 0, 0, printer_y), 0, printer_y);

    gcodeX = constrain(map(printX2, 0, width, 0, printer_x), 0, printer_x);
    gcodeY = constrain(map(printY2, height, 0, 0, printer_y), 0, printer_y);

    printZconstrain = constrain(printZ, 1, printer_z/layerHeight);//Makes you unable to break the limit of your printer Z-axis.

    //calculate the amount of filement needed for a single line (Pythagorean theorem)
    float lineLength = sqrt(sq(abs(startgcodeX-gcodeX))+sq(abs(startgcodeY-gcodeY))); //Using Pythagorean theorem to calculate the length of the line for the printer
    filament_calculation += abs((lineLength*layerHeight*nozzleWidth)/sq(filamentThickness))*(amount_of_filament/100); //Calculating the amount of filament needed for the printline
  }

  void currentZaxis() {
    current_Zaxis = abs(layerHeight*printZconstrain); //Remembers the Z-axis to remove the print nozzle after a print.
    if (current_Zaxis > printer_z/layerHeight-10) { //secures the printer to be unable to exceed the maximum height.
      current_Zaxis = printer_z/layerHeight-10;
    }
  }

  void myTranslate(float x, float y) {
    translateX+=x;
    translateY+=y;
  }
  void moveTo(float x, float y, float z) {
    moveX = x;
    moveY = y;
    moveZ = z;
  }
  void lineTo(float x, float y, float z) {
    printLine(moveX+translateX, moveY+translateY, x+translateX, y+translateY, z);
    moveTo(x, y, z);
  }
}
