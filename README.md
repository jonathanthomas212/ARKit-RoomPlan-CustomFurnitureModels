# ARKit-RoomPlan-CustomFurnitureModels
Extended functionality to replace RoomPlan default bounding boxes with custom furniture models 

RoomPlan includes classifications for the following objects:
- storage
- refrigerator
- stove
- bed
- washerDryer
- toilet
- bathtub
- oven
- dishwasher
- table
- sofa
- chair
- television

Custom models can be added by placing usdz files with the corresponding filename in the furnitureModels folder

RoomScanVC contains methods to create a RoomPlan object, reconstruct the view using SceneKit and replace classified objects with custom furniture models 

