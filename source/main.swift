import Cocoa

final class PetView: NSView {
    var cells: [[NSImage]] = []
    var row = 0, frameIndex = 0
    var ticks = 0, actionUntil = Date.distantPast
    var pointerFollow = true
    var timer: Timer?
    var dragMouse = NSPoint.zero, dragOrigin = NSPoint.zero
    var savePosition: (() -> Void)?
    let counts = [6,8,8,4,5,0,0,6,0,0,0]
    let stateNames = ["idle","running-right","running-left","waving","jumping","","","running","","",""]
    override var acceptsFirstResponder: Bool { false }
    init(atlas: URL) {
        super.init(frame: NSRect(x:0,y:0,width:192,height:208))
        let root=Bundle.main.resourceURL!.appendingPathComponent("Frames")
        for r in 0..<11 {
            var line:[NSImage]=[]
            for c in 0..<counts[r] {
                let url=root.appendingPathComponent(stateNames[r]).appendingPathComponent(String(format:"%02d.png",c))
                guard let image=NSImage(contentsOf:url) else { fatalError("Missing animation frame: \(url)") }
                line.append(image)
            }
            cells.append(line)
        }
        timer = Timer.scheduledTimer(withTimeInterval:0.14,repeats:true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!,forMode:.common)
        setAccessibilityLabel("Doro 桌面宠物，拖动移动，右键选择动作")
    }
    required init?(coder:NSCoder) { fatalError() }
    func play(_ state:Int,seconds:Double=3) { row=state;frameIndex=0;actionUntil=Date().addingTimeInterval(seconds);needsDisplay=true }
    func step() {
        ticks += 1
        if Date() < actionUntil { frameIndex = (frameIndex+1)%counts[row] }
        else {
            row=0;frameIndex=ticks%6
        }
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.clear.setFill();bounds.fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        cells[row][frameIndex].draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1)
    }
    override func mouseDown(with event:NSEvent) {
        if event.clickCount>=2 { play(4);return }
        dragMouse=NSEvent.mouseLocation;dragOrigin=window?.frame.origin ?? .zero
    }
    override func mouseDragged(with event:NSEvent) {
        let now=NSEvent.mouseLocation
        let dx=now.x-dragMouse.x,dy=now.y-dragMouse.y
        window?.setFrameOrigin(NSPoint(x:dragOrigin.x+dx,y:dragOrigin.y+dy))
        play(dx>=0 ? 1:2,seconds:0.25)
    }
    override func mouseUp(with event:NSEvent) {
        savePosition?()
        // Preserve the jump started by the second mouse-down of a double click.
        if event.clickCount < 2 { play(3,seconds:1.2) }
    }
    override func rightMouseDown(with event:NSEvent) { if let m=menu { NSMenu.popUpContextMenu(m,with:event,for:self) } }
}
final class PetPanel:NSPanel { override var canBecomeKey:Bool { false };override var canBecomeMain:Bool { false } }
final class AppDelegate:NSObject,NSApplicationDelegate {
    var panel:PetPanel!,pet:PetView!,status:NSStatusItem!
    var storage:URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Doro", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { NSLog("Unable to create Doro storage: %@", error.localizedDescription) }
        return directory
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier:"local.doro.desktop").count>1 { NSApp.terminate(nil);return }
        NSApp.setActivationPolicy(.accessory)
        let atlas=Bundle.main.resourceURL!
        pet=PetView(atlas:atlas)
        let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        var origin=NSPoint(x:screen.maxX-230,y:screen.minY+40)
        if let data=try? Data(contentsOf:storage.appendingPathComponent("position.json")),let p=try? JSONSerialization.jsonObject(with:data) as? [String:Double],let x=p["x"],let y=p["y"],NSScreen.screens.contains(where:{$0.frame.intersects(NSRect(x:x,y:y,width:192,height:208))}) { origin=NSPoint(x:x,y:y) }
        panel=PetPanel(contentRect:NSRect(origin:origin,size:pet.frame.size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
        panel.level = .floating;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        panel.contentView=pet
        pet.savePosition={ [weak self] in self?.save() }
        let menu=NSMenu()
        add(menu,"Doro · 独立桌面宠物",nil)
        menu.addItem(.separator())
        for (title,state) in [("挥手",3),("跳跃",4),("思考（动作演示）",7)] { let item=add(menu,title,#selector(action(_:)));item.tag=state }
        menu.addItem(.separator())
        add(menu,"回到屏幕角落",#selector(reset))
        add(menu,"隐藏／显示",#selector(toggle))
        add(menu,"打开存储文件夹",#selector(folder))
        add(menu,"退出 Doro",#selector(quit))
        pet.menu=menu;status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);status.button?.title="Doro";status.menu=menu
        panel.orderFrontRegardless()
    }
    @discardableResult func add(_ m:NSMenu,_ title:String,_ selector:Selector?)->NSMenuItem { let i=NSMenuItem(title:title,action:selector,keyEquivalent:"");i.target=self;m.addItem(i);return i }
    @objc func action(_ sender:NSMenuItem) { pet.play(sender.tag,seconds:5) }
    @objc func follow(_ sender:NSMenuItem) { pet.pointerFollow.toggle();sender.state=pet.pointerFollow ? .on:.off }
    @objc func reset() { if let s=NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x:s.maxX-230,y:s.minY+40));save();panel.orderFrontRegardless() } }
    @objc func toggle() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func folder() { NSWorkspace.shared.open(storage) }
    @objc func quit() { save();NSApp.terminate(nil) }
    func save() { let p=panel.frame.origin;if let data=try? JSONSerialization.data(withJSONObject:["x":p.x,"y":p.y]) { try? data.write(to:storage.appendingPathComponent("position.json"),options:.atomic) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
}
if CommandLine.arguments.contains("--self-test") {
    let root=Bundle.main.resourceURL!.appendingPathComponent("Frames")
    let active=[("idle",6),("running-right",8),("running-left",8),("waving",4),("jumping",5),("running",6)]
    for (name,count) in active { for c in 0..<count {
        let url=root.appendingPathComponent(name).appendingPathComponent(String(format:"%02d.png",c))
        guard let data=try? Data(contentsOf:url),let rep=NSBitmapImageRep(data:data),rep.pixelsWide==192,rep.pixelsHigh==208 else { print("FAIL frame \(url)");exit(1) }
    } }
    print("PASS: all 37 active standalone animation frames loaded at192x208")
    exit(0)
}
let application=NSApplication.shared
let delegate=AppDelegate()
application.delegate=delegate
application.run()
