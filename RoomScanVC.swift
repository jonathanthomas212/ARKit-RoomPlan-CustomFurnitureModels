

import UIKit
import RoomPlan
import ModelIO
import SceneKit
import Alamofire
import MetalKit

@available(iOS 16.0, *)
class RoomScanVC: UIViewController {
    
    private var roomCaptureView: RoomCaptureView!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var toggleButton: UIButton!
    
    var furnitureView = false
    var sceneView: SCNView!
    var loadingView: UploaderProgressView!
    var minX:Float = 0.0
    var maxX:Float = 0.0
    var minZ:Float = 0.0
    var maxZ:Float = 0.0
    
    
    
    var url: URL?
    
    private var roomCaptureSessionConfig: RoomCaptureSession.Configuration = RoomCaptureSession.Configuration()
    var isScanning: Bool = false
    private var finalResults: CapturedRoom?
    override func viewDidLoad() {
        super.viewDidLoad()
    
        self.toggleButton.isHidden = true
        self.setupRoomCaptureView()
        // Do any additional setup after loading the view.

    }
    private func setupRoomCaptureView() {
        let boundingBox = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height-100)
        roomCaptureView = RoomCaptureView(frame: boundingBox)
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self

        view.insertSubview(roomCaptureView, at: 0)

    }
    @IBAction func back(_ sender: Any) {
        
        if self.isScanning {
            self.stopSession()
        }
        self.navigationController?.popViewController(animated: true)
    }
    @IBAction func recordSession(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if self.isScanning {
            self.stopSession()
        } else {
            self.startSession()
        }
    }
    
    
    private func startSession() {
        isScanning = true
        roomCaptureView?.captureSession.run(configuration: roomCaptureSessionConfig)
        self.backButton.isEnabled = true
    }
    
    private func stopSession() {
        isScanning = false
        roomCaptureView?.captureSession.stop()
        
        self.backButton.isEnabled = true
        UIView.animate(withDuration: 0.5) {
            self.recordButton.isHidden = true
        }
    }
    
    //toggle between bounding boxes and furniture view
    @IBAction func toggleButtonPressed(_ sender: Any) {
        if furnitureView == false {
            view.addSubview(sceneView)
            view.bringSubviewToFront(toggleButton)
            furnitureView = true
        } else {
            sceneView.removeFromSuperview()
            furnitureView = false
        }
    }
}

@available(iOS 16.0, *)
extension RoomScanVC: RoomCaptureViewDelegate, RoomCaptureSessionDelegate {

    // Decide to post-process and show the final results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        let builder = RoomBuilder(options: .beautifyObjects)
        Task(priority: .background) {
            finalResults = try? await builder.capturedRoom(from: roomDataForProcessing)
        }
        return true
    }

    // Access the final post-processed results.
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        
        //initialize sceneview to view our edited model
        sceneView = SCNView(frame: view.bounds)
        sceneView.scene = SCNScene()
        
        // Create and add a camera node
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 10)
        sceneView.scene!.rootNode.addChildNode(cameraNode)

        // Create and add a light node
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        sceneView.scene!.rootNode.addChildNode(lightNode)
        
        // Enable default lighting and allows the user to manipulate the camera
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)

        let rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        sceneView.addGestureRecognizer(rotateGesture)
        
        //get information from roomscan and add furniture models with appropriate scale and direction
        onModelReady(model: processedResult)
        self.toggleButton.isHidden = false
        
        
        return
    }
    
    //create the reconstructed model using the informatin captured from roomplan
    private func onModelReady(model: CapturedRoom) {
            let walls = getAllNodes(for: model.walls,
                                    length: 0.1,
                                    contents: UIImage(named: "wallTexture"))
            walls.forEach { sceneView.scene!.rootNode.addChildNode($0) }
            let doors = getAllNodes(for: model.doors,
                                    length: 0.13, //make this 0.11 to avoid z-fighting
                                    contents: UIColor.lightGray.withAlphaComponent(0.5))
            doors.forEach { sceneView.scene!.rootNode.addChildNode($0) }
            let windows = getAllNodes(for: model.windows,
                                      length: 0.13,
                                      contents: UIColor.blue.withAlphaComponent(0.5))
            windows.forEach { sceneView.scene!.rootNode.addChildNode($0) }
            let openings = getAllNodes(for: model.openings,
                                      length: 0.13,
                                       contents: UIColor.lightGray.withAlphaComponent(0.5))
            openings.forEach { sceneView.scene!.rootNode.addChildNode($0) }
        
            if let floorSurface = model.walls.first {
                let floorNode = createFloorNode(with: floorSurface)
                sceneView.scene!.rootNode.addChildNode(floorNode)
            }
            
            //replace the following objects with furniture models
            let allCategories: [CapturedRoom.Object.Category] = [
                .storage,
                .refrigerator,
                .stove,
                .bed,
                .washerDryer,
                .toilet,
                .bathtub,
                .oven,
                .dishwasher,
                .table,
                .sofa,
                .chair,
                .television
            ]
        
            allCategories.forEach { category in
                let scannedObjects = model.objects.filter { $0.category == category }
                let objectsNode = getAllNodes(for: scannedObjects, category: category)
                objectsNode.forEach { sceneView.scene?.rootNode.addChildNode($0) }
            }
        }
        
        //surfaces (walls, doors, windows, openings)
        private func getAllNodes(for surfaces: [CapturedRoom.Surface], length: CGFloat, contents: Any?) -> [SCNNode] {
            var nodes: [SCNNode] = []
            surfaces.forEach { surface in
                let width = CGFloat(surface.dimensions.x)
                let height = CGFloat(surface.dimensions.y)
                let node = SCNNode()
                node.geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.0)
                node.geometry?.firstMaterial?.diffuse.contents = contents
                node.transform = SCNMatrix4(surface.transform)
                nodes.append(node)
                
                //track min and max wall positions for floor
                if surface.category == .wall {
                    let x_pos = surface.transform.columns.3.x
                    let z_pos = surface.transform.columns.3.z
                    
                    minX = min(minX, x_pos - (surface.dimensions.x / 2))
                    maxX = max(maxX, x_pos + (surface.dimensions.x / 2))
                    minZ = min(minZ, z_pos - (surface.dimensions.z / 2))
                    maxZ = max(maxZ, z_pos + (surface.dimensions.z / 2))
                }
            }
            return nodes
        }

        //furniture
        private func getAllNodes(for objects: [CapturedRoom.Object], category: CapturedRoom.Object.Category) -> [SCNNode] {
            var nodes: [SCNNode] = []
            
            let categoryString = String(describing: category)
            if let objectUrl = Bundle.main.url(forResource: categoryString, withExtension: "usdz"),
               let objectScene = try? SCNScene(url: objectUrl),
               let objectNode = objectScene.rootNode.childNodes.first {
                objects.enumerated().forEach { index, object in
                    let node = objectNode.clone()
                    
                    
                    // Apply transformation (rotation, translation) to entire object hierarchy
                    node.childNodes.forEach { childNode in
                        
                        // Calculate the bounding box of the object node and its dimensions
                        let (min, max) = childNode.boundingBox
                        let x = max.x - min.x
                        let y = max.y - min.y
                        let z = max.z - min.z
                        
                        //calculate scaling factors (model will stretch to match roomplans bounding box)
                        let xScalingFactor = object.dimensions.x / x
                        let yScalingFactor = object.dimensions.y / y
                        let zScalingFactor = object.dimensions.z / z
                        let scale = SCNVector3(xScalingFactor, yScalingFactor, zScalingFactor)
                        
                    
                        childNode.transform = SCNMatrix4(object.transform)
                        childNode.scale = scale
                    }
                    
                    nodes.append(node)
                }
            }
            //no usdz file, use box instead
            else {
                objects.enumerated().forEach { index, object in
                    let width = CGFloat(object.dimensions.x)
                    let height = CGFloat(object.dimensions.y)
                    let length = CGFloat(object.dimensions.z)
                    let node = SCNNode()
                    node.geometry = SCNBox(width: width, height: height, length: length, chamferRadius: 0.0)
                    node.geometry?.firstMaterial?.diffuse.contents = UIImage(named: "wallTexture")
                    node.transform = SCNMatrix4(object.transform)
                    nodes.append(node)
                }
            }
            return nodes
        }
    
        
        private func createFloorNode(with surface: CapturedRoom.Surface) -> SCNNode {
            let width = CGFloat(abs(maxX-minX)) * 1.2 //buffer to minimize overhang
            let length = CGFloat(abs(maxZ-minZ)) * 1.2
            let height: CGFloat = 0.1 // Adjust the floor height as needed
            
            let y_pos = surface.transform.columns.3.y - (surface.dimensions.y / 2)

            let floorGeometry = SCNBox(width: max(width,length), height: height, length: max(width,length), chamferRadius: 0.0)
            floorGeometry.firstMaterial?.diffuse.contents = UIColor.lightGray

            let floorNode = SCNNode(geometry: floorGeometry)
            
            //align with first wall
            floorNode.transform = SCNMatrix4(surface.transform)
            
            //move to caclulated center and at ground level
            floorNode.position = SCNVector3((minX+maxX)/2 ,y_pos ,(minZ+maxZ)/2)

            return floorNode
        }




        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let sceneView = gesture.view as? SCNView else { return }
            let scale = Float(gesture.scale)
            let cameraNode = sceneView.pointOfView!
            cameraNode.camera?.fieldOfView /= CGFloat(scale)
            gesture.scale = 1.0
        }

        @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            guard let sceneView = gesture.view as? SCNView else { return }
            
            let rotation = Float(gesture.rotation)
            let cameraNode = sceneView.pointOfView!
            
            // Create a rotation matrix for each axis
            let rotationX = SCNMatrix4MakeRotation(rotation, 1, 0, 0)
            let rotationY = SCNMatrix4MakeRotation(rotation, 0, 1, 0)
            let rotationZ = SCNMatrix4MakeRotation(rotation, 0, 0, 1)
            
            // Apply the rotation matrices to the camera's transform
            var newTransform = cameraNode.transform
            newTransform = SCNMatrix4Mult(rotationX, newTransform)
            newTransform = SCNMatrix4Mult(rotationY, newTransform)
            newTransform = SCNMatrix4Mult(rotationZ, newTransform)
            
            // Update the camera's transform
            cameraNode.transform = newTransform
            
            gesture.rotation = 0.0
        }




}

