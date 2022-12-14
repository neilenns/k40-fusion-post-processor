/**
  Copyright (C) 2018 by Autodesk, Inc.
  All rights reserved.
*/

description = "K40 Whisperer";
vendor = "none";
vendorUrl = "https://www.scorchworks.com/K40whisperer/k40whisperer.html";
legal = "Copyright (C) 2018 by Autodesk, Inc.";
certificationLevel = 2;

longDescription = "Generic post for K40 Whisperer. The post will output the toolpath as SVG graphics which can then be cut directly from K40 Whisperer.";

extension = "svg";
mimetype = "image/svg+xml";
setCodePage("utf-8");

capabilities = CAPABILITY_JET;

minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(90); // avoid potential center calculation errors for CNC
allowHelicalMoves = true;
allowedCircularPlanes = (1 << PLANE_XY); // only XY arcs

// global prooperties variable
properties = null;
// made available for testing
function resetProperties() {
    properties = {
      lineWidth: 0.1, // how wide lines are in the SVG
      margin: 2, // margin in mm
      checkForRadiusCompensation: false, // if enabled throw an error if compensation in control is used
      doNotFlipYAxis: false,
      useWorkArea: false, // center the toolpath in the machines work area, off by default
      autoStockPoint: true, // automatically translate the output paths for strage stock points, see the whole image no matter what you select
      // Glowforge Cutting area: aprox. 19.5″ (495 mm) wide and 11″ (279 mm) deep
      workAreaWidth: 495, // width in mm used when useWorkArea is enabled
      workAreaHeight: 279, // height in mm used when useWorkArea is enabled
  };
}
resetProperties();

// user-defined property definitions
propertyDefinitions = {
  lineWidth: {title: "SVG Stroke Width(mm)", description: "The width of lines in the SVG in mm.", type: "number"},
  margin: {title: "Margin(mm)", description: "Sets the margin in mm when 'Crop to Workpiece' is used.", type: "number"},
  checkForRadiusCompensation: {title: "Check Sideways Comp.", description: "Check every operation for Sideways Compensation 'In Computer'. If this is not configured, throw an error.", type: "boolean"},
  doNotFlipYAxis: {title: "Flip Model", description: "If your part is upside down, check this box to flip it over. (Tip: checking 'Flip Z Axis' in the CAM setup also fixes this)", type: "boolean"},
  useWorkArea: {title:"Use Work Area", description:"Center the toolpaths in an image the size of the defined Work Area.", type:"boolean"},
  autoStockPoint: {title:"Auto Stock Point", description:"Make the final image completly visible reguardless of the selected stock point.", type:"boolean"},
  workAreaWidth: {title:"Work Area Width(mm", description:"Work Area Width in mm, used when 'Crop to Workpiece' is disabled. Typically the max cutting width of the Glowforge.", type:"number"},
  workAreaHeight: {title:"Work Area Height(mm)", description:"Height in mm, used when 'Crop to Workpiece' is disabled. Typically the max cutting height of the Glowforge.", type:"number"},
};

var POST_URL = "https://cam.autodesk.com/hsmposts?p=k40whisperer";

// Recommended colors for color mapping.
var COLOR_RED = "#FF0000";
var COLOR_BLACK = "#000000";

/** Global State **/
function reset() {
  return {
    // ConverterFormat: converted from IN to MM as needed
    xyzFormat: createFormat({decimals:(3), scale:(unit === IN) ? 25.4 : 1}),
    // clamp to 3 decimals but dont convert
    decimalFormat: createFormat({decimals:(3), scale: 1}),
    // the hex string of the current color
    currentHexColor: null,
    // track if the next path element can be a move command
    allowMoveCommandNext: null,
    // is the work area too small?
    workAreaTooSmall: false,
    // is the llaser currently on?
    isLaserOn: false
  };
}
var state = null;

// should the current sction be cut (using a stroke) or etched (using a fill)?
var useFillForSection = false;

/**
 * For Etch/Vaporize/Engrave, returns fill settings, otherwise none
 */
function fill() {
  if (useFillForSection) {
    return "fill=\"" + state.currentHexColor + "\"";
  }
  return "fill=\"none\"";
}

/**
 * For through cuts, returns stroke settings, otherwise none
 */
function stroke() {
  if (useFillForSection) {
    return "stroke=\"none\"";
  }
  return "stroke=\"" + state.currentHexColor + "\" stroke-width=\"" + properties.lineWidth + "\"";
}

// update the allowMoveCommandNext flag
function allowMoveCommand() {
  state.allowMoveCommandNext = true;
}

var activePathElements = [];
function addPathElement() {
  var args = [].slice.call(arguments);

  // only allow moves (M) in the SVG after the laser has been turned off and comes back on again
  if (args[0] === "M") {
    if (state.allowMoveCommandNext) {
      // reset the flag to wait for the next laser power cycle
      state.allowMoveCommandNext = false;
    }
    else {
      // skip rendering this move command since the laser has not been turned off
      return;
    }
  }

  activePathElements.push(args.join(" "));
}

function finishPath() {
  if (!activePathElements || activePathElements.length === 0) {
    error('An operation resulted in no detectable paths!');
    return;
  }

  var opComment = hasParameter("operation-comment") ? getParameter("operation-comment") : "[No Title]";
  var safeOpComment = opComment.replace(/\s+/g, '_');

  writeln("<g id=\"" + (safeOpComment + "_" + (1 + currentSection.getId())) + "\" inkscape:label=\"" + opComment + "\" inkscape:groupmode=\"layer\">");
  writeln("    <title>" + opComment + " (" + localize("Op") + ": " + (1 + currentSection.getId()) + "/" + getNumberOfSections() + ")</title>");
  writeln("    <path d=\"" + activePathElements.join("\n             ") + "\" "
    + fill() 
    + " "
    + stroke()
    + "/>")
  writeln("</g>");
  activePathElements = [];
  allowMoveCommand();
}

// return true if the program should halt because of missing radius compensation in the computer.
function isRadiusCompensationInvalid() {
  if (properties.checkForRadiusCompensation === true && (radiusCompensation != RADIUS_COMPENSATION_OFF)) {
    error("Operation: " + (1 + currentSection.getId()) + ". The Sideways Compensation type 'In Control' is not supported. This must be set to 'In Computer' in the passes tab.");
  }
}

/** Returns the given spatial value in MM. */
function toMM(value) {
  return value * ((unit === IN) ? 25.4 : 1);
}

function printVector(v) {
  return v.x + "," + v.y;
}

function onOpen() {
  if (properties.margin < 0) {
    error(localize("Margin must be 0 or positive."));
    return;
  }

  // reset all per-run state
  state = reset();
  
  // convert everything to mm once up front:
  var box = {
    upper: {
      x: toMM(getWorkpiece().upper.x),
      y: toMM(getWorkpiece().upper.y)
    },
    lower: {
      x: toMM(getWorkpiece().lower.x),
      y: toMM(getWorkpiece().lower.y)
    }
  };

  var dx = box.upper.x - box.lower.x;
  var dy = box.upper.y - box.lower.y;

  // add margins to overall SVG size
  var width = dx + (2 * properties.margin);
  var height = dy + (2 * properties.margin);
  
  if (properties.useWorkArea === true) {
    // no margins in useWorkArea mode, you get the work area as your margins!
    width = Math.max(properties.workAreaWidth, dx);
    height = Math.max(properties.workAreaHeight, dy);
    state.workAreaTooSmall = width > properties.workAreaWidth || height > properties.workAreaHeight;
  }
  /*
   * Compensate for Stock Point, SVG Origin, Z axis orientation and margins
   *
   * The *correct* stock point to select is the lower left corner and the right Z axis orientation is pointing up from the stock towards the laser.
   * But to make the learning curve a little gentler we will compensate if you didnt do that.
   *
   * Auto Stock Point Compensation: 
   * First, any stock point will produce the same image, here we correct for the stock point with a translation of the entire SVG contents
   * in x and y. We want to use the extents of the X and Y axes. Normally X comes from the lower right corner of the stock and Y from the 
   * upper left (assuming a CAM origin in the lower left corner).
   *
   * Y Axis in SVG vs CAM: 
   * If we do nothing the image would be upside down because in SVG the Y origin is at the TOP of the image (see https://www.w3.org/TR/SVG/coords.html#InitialCoordinateSystem).
   * So normally the Y axis must be flipped to compensate for this by scaling it to -1.
   * 
   * Incorrect Z Axis Orientation:
   * If the user has the Z axis pointing into the stock the SVG image will be upside down (flipped in Y, twice!). This is annoying and is not obvious to fix
   * because X and Y look right in the UI. So the "Flip Model" parameter is provided and does *magic* by turning off the default Y flipping. Now the Y axis is only flipped once
   * like we need for the SVG origin. But the *lower* box point has to be used to get the Y extent in this case because the *CAM* is upside down (CAM origin is top left corner).
   * Unfortunatly the stock point selection changes the ratio between Y values in the upper and lower stock points, so its impossible to detect this without assuming a stock point.
   * So this is as good as we can do.
   *
   * Margins:
   * Add 1 magin width to these numbers so the image is centred.
   */
  var yAxisScale = properties.doNotFlipYAxis ? 1 : -1;
  var translateX = 0;
  var translateY = 0;

  if (properties.useWorkArea === true) {
    // FIXME: this is probably wrong if the design turns out to be bigger than the work area, e.g. (width - dx) will be negative!
    translateX = (-box.lower.x + ((width - dx) / 2));
    translateY = (box.upper.y + ((height - dy) / 2));
  }
  else if (properties.autoStockPoint === true) {
    translateX = (-1 * box.lower.x) + properties.margin;
    translateY = (-1 * yAxisScale * (properties.doNotFlipYAxis ? box.lower.y : box.upper.y)) + properties.margin;
  }
  // else dont translate anythng.

  writeln("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>");
  writeln("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" width=\"" + width + "mm\" height=\"" + height + "mm\" viewBox=\"0 0 " + width + " " + height + "\">");
  writeln("<desc>Created with " + description + " for Fusion 360. To download visit: " + POST_URL + "</desc>");

  // write a comment explaining what info we got from the CAM system about the stock and coordinate system
  writeln("<!-- CAM Setup Info:"
    + "\nWork Area Width: " + width + "mm"
    + "\nWork Area Height: " + height + "mm"
    + "\nWork Area Too Small?: " + state.workAreaTooSmall
    + "\nStock box Upper Right: " + printVector(box.upper)
    + "\nStock box Lower Left: " + printVector(box.lower)
    + "\nOrigin: " + printVector(getCurrentPosition())
    + "\n-->");

  // translate + scale operation to flip the Y axis so the output is in the same x/y orientation it was in Fusion 360
  writeln("<g id=\"global-translation-frame\" transform=\"translate(" + state.decimalFormat.format(translateX) + ", " + state.decimalFormat.format(translateY) + ") scale(1, " + yAxisScale + ")\">");
}

function onClose() {
  writeln("</g>");
  // draw an untranslated box to represent the work are boundary on top of everything
  if (state.workAreaTooSmall === true) {
    writeln("<rect id=\"work-area-boundary\" x=\"" + 0 + "\" y=\"" + 0 + "\" width=\"" + state.decimalFormat.format(properties.workAreaWidth) + "\" height=\"" + state.decimalFormat.format(properties.workAreaHeight) + "\" style=\"fill:none;stroke:red;stroke-width:1;\"/>");
  }
  writeln("</svg>");
}

function onComment(text) {
  writeln('<!--' + text + '-->');
}

function onSection() {
  switch (tool.type) {
  case TOOL_WATER_JET: // allow any way for Epilog
    warning(localize("Using waterjet cutter but allowing it anyway."));
    break;
  case TOOL_LASER_CUTTER:
    break;
  case TOOL_PLASMA_CUTTER: // allow any way for Epilog
    warning(localize("Using plasma cutter but allowing it anyway."));
    break;
  case TOOL_MARKER: // allow any way for Epilog
    warning(localize("Using marker but allowing it anyway."));
    break;
  default:
    error(localize("The CNC does not support the required tool."));
    return;
  }

  // use Jet Mode to decide if the shape should be filled or have no fill
  switch (currentSection.jetMode) {
  case JET_MODE_THROUGH:
    useFillForSection = false;
    state.currentHexColor = COLOR_RED;
    break;
  case JET_MODE_ETCHING:
  case JET_MODE_VAPORIZE:
    useFillForSection = true
    state.currentHexColor = COLOR_BLACK;
    break
  default:
    error(localize("Unsupported cutting mode."));
    return;
  }

  var remaining = currentSection.workPlane;
  if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
    error(localize("Tool orientation is not supported."));
    return;
  }
  setRotation(remaining);
}

function onParameter(name, value) {
}

function onDwell(seconds) {
}

function onCycle() {
}

function onCyclePoint(x, y, z) {
}

function onCycleEnd() {
}

function onPower(isLaserPowerOn) {
  // if the laser goes from off to on, this happens after a move, so a M should be emitted in the SVG
  // this check debounces multiple power on caommands in case the way they are emitted ever changes
  if (!state.isLaserOn && isLaserPowerOn) {
    allowMoveCommand();
  }

  state.isLaserOn = isLaserPowerOn;
}

// validate that the laser is on and that the movement type is a cutting move
function isCuttingMove(movement) {
  return state.isLaserOn && (movement === MOVEMENT_CUTTING || movement == MOVEMENT_REDUCED || movement == MOVEMENT_FINISH_CUTTING);
}

function writeLine(x, y) {
  if (!isCuttingMove(movement)) {
    return;
  }

  isRadiusCompensationInvalid();
  
  var start = getCurrentPosition();
  if ((state.xyzFormat.format(start.x) == state.xyzFormat.format(x)) &&
      (state.xyzFormat.format(start.y) == state.xyzFormat.format(y))) {
    log('vertical move ignored');
    return; // ignore vertical
  }

  addPathElement("M", state.xyzFormat.format(start.x), state.xyzFormat.format(start.y));
  addPathElement("L", state.xyzFormat.format(x), state.xyzFormat.format(y));
}

function onRapid(x, y, z) {
  writeLine(x, y);
}

function onLinear(x, y, z, feed) {
  writeLine(x, y);
}

function onRapid5D(x, y, z, dx, dy, dz) {
  onRapid(x, y, z);
}

function onLinear5D(x, y, z, dx, dy, dz, feed) {
  onLinear(x, y, z);
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (!isCuttingMove(movement)) {
    return;
  }

  isRadiusCompensationInvalid();

  var start = getCurrentPosition();

  var largeArc = (getCircularSweep() > Math.PI) ? 1 : 0;
  var sweepFlag = isClockwise() ? 0 : 1;
  addPathElement("M", state.xyzFormat.format(start.x), state.xyzFormat.format(start.y));
  addPathElement("A", state.xyzFormat.format(getCircularRadius()), state.xyzFormat.format(getCircularRadius()), 0, largeArc, sweepFlag, state.xyzFormat.format(x), state.xyzFormat.format(y));
}

function onCommand() {
}

function onSectionEnd() {
  finishPath();
}
