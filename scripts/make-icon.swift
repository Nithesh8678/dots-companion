import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let pixels = size*scale
  let image = NSImage(size: NSSize(width: pixels, height: pixels))
  image.lockFocus()
  let p = CGFloat(pixels)
  NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.09, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x:p*0.045,y:p*0.045,width:p*0.91,height:p*0.91), xRadius:p*0.22,yRadius:p*0.22).fill()
  NSColor(calibratedRed:0.72,green:0.85,blue:0.49,alpha:1).setFill()
  NSBezierPath(ovalIn: NSRect(x:p*0.18,y:p*0.18,width:p*0.64,height:p*0.64)).fill()
  NSColor(calibratedRed:0.12,green:0.16,blue:0.08,alpha:1).setFill()
  for x in [0.36,0.565] { NSBezierPath(roundedRect:NSRect(x:p*x,y:p*0.435,width:p*0.075,height:p*0.13),xRadius:p*0.0375,yRadius:p*0.0375).fill() }
  image.unlockFocus()
  let data=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
  try data.write(to:URL(fileURLWithPath:"\(output)/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
 }
}
