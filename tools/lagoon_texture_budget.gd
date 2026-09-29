extends SceneTree
## Decoded image storage, not a claim about device peak/GPU memory or frame rate.
func _initialize() -> void:call_deferred("run")
func run() -> void:
 root.get_node("SaveSystem").set_process(false)
 var report: Dictionary={"frames":[],"decoded_bytes_with_mipmaps":0}
 for i in 32:
  var path: String="res://art/environment/pelagic_crown-crown_lagoon-motion-%02d.png" % i
  var texture: Texture2D=load(path)
  var im: Image=texture.get_image()
  var bytes: int=im.get_data().size()
  report.frames.append({"frame":i,"size":str(im.get_size()),"bytes":bytes,"mipmaps":im.has_mipmaps()})
  report.decoded_bytes_with_mipmaps+=bytes
 var before:=0
 var folder:=OS.get_environment("LAGOON_PREVIOUS_ART")
 for i in 32:
  var im:=Image.load_from_file(folder+"/pelagic_crown-crown_lagoon-motion-%02d.png" % i)
  im.generate_mipmaps()
  before+=im.get_data().size()
 report["previous_decoded_bytes_with_mipmaps"]=before
 report["additional_decoded_bytes"]=report.decoded_bytes_with_mipmaps-before
 print(JSON.stringify(report))
 var output:=OS.get_environment("LAGOON_BUDGET_REPORT")
 if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
 quit()
