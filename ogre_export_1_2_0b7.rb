# Sketchup To Ogre Exporter  Version 1.2.0b7
# Partially rewritten by Fabrizio Nunnari <fnunnari@vrmmp.it>
# based on v1.0.1 Written by Kojack
#
# TODO
# - Some objects are not centered. It is due to the Axes repositioning. Must detect current axes position and transform object accodingly.
#
# 1.2.0b7
# - Added normals normalization. Fixes materials luminance in Ogre.
#
# 1.2.0b6
# - Some code clean up
# - Exporting also backfaces
#
# 1.2.0b5
# - Reworked some info puts
# - Saves textures only for used materials
# - Fixed UVMap texture export for inherited materials
# - Changed ogre material write
# - renamed the config file in order to co-exist with the exporter from Kojack :-)
#
# 1.2.0b4
# - Fixed textures UV exporting using UVHelper (Thanks again to Kojack from the Ogre community for the hints)
#
# 1.2.0b3
# - Polished code and some indentation
# - Adjusted material renaming
# - Added documentation.
#
# 1.2.0b2
# - revrote texture handling:
#     - make meshes reference the copied texture, and not the original names
#     - Textures are loaded only once and written one by one, with a unique name
#     - avoid loading the same texture several times
# - materials are get not only for faces but also for intermediate components (Groups, and more)
# - Possibility to add a unique prefix, in order to avoid name collisions.
#
# 1.0.5
# - Removes also slashes from the path names
# - Set color values also if there is a texture
#
# 1.0.4
# - remove spaces only for files that really have some
#
# 1.0.3
# - removed spaces from texture names (brutal approach: exported textures are renamed, but can't find the way to set tha filename into a texture instance)
#
# 1.0.2
#
# - removed the dirty texture dimension export in materials with textures
# - generating a unique id as post-fix for material names
# - not exporting SketchupDefault material
# - avoid having nil in materials hash
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place - Suite 330, Boston, MA 02111-1307, USA, or go to
# http://www.gnu.org/copyleft/lesser.txt.


# Comment the code inside debug_print to boost export speed. Remove the comment for detailed export report.
def debug_print s	
	print s
end

def append_paths(p,f)
	if p[-1,1] == "\\" or p[-1,1] == "/"
		p+f
	else
		p+"\\"+f
	end
end

#def point_to_vector(p)
#	Geom::Vector3d.new(p.x,p.y,p.z)
#end

def transform_to_s t
	a = t.to_a.map {|e| e.to_s}
	s = a[0] + " " + a[1] + " " + a[2] + " " + a[3] + "\n" + a[4] + " " +a[5] + " " +a[6]+ " " +a[7] + "\n"	+ a[8] + " " +a[9] + " " +a[10]+ " " +a[11] + "\n" + a[12] + " " +a[13] + " " +a[14]+ " " +a[15] + "\n"
	return s
end

# This class summarize the infomation needed to export a Material for Ogre.
class OgreMaterial
	attr_writer :name, :color, :textureName, :textureHandle, :textureSize, :textureSource, :textureSourceFaceFront, :useAlpha, :alpha
	attr_reader :name, :textureName, :textureHandle, :textureSize, :textureSource, :textureSourceFaceFront, :useAlpha
		
	def writeOut s

		# The specular color will be "a bit more" that the diffuse, but always clamped to 1.0
		specular = @color.collect { |c| [c*1.2, 1.0].min }
		shininess = 15.0
	
		s.print	"material #{@name}\n" \
				"{\n"\
				"  technique\n"\
				"  {\n"\
				"    pass\n"\
				"    {\n"
		if @useAlpha
			s.print	"      scene_blend alpha_blend\n"\
					"      depth_check on\n"\
					"      depth_write off\n"\
					"      ambient #{@color[0]} #{@color[1]} #{@color[2]} #{@alpha}\n"\
					"      diffuse #{@color[0]} #{@color[1]} #{@color[2]} #{@alpha}\n"\
					"      specular #{specular[0]} #{specular[1]} #{specular[2]} #{@alpha} #{shininess}\n"\
					"      emissive 0.0 0.0 0.0 1.0\n"
		else
			s.print	"      ambient #{@color[0]} #{@color[1]} #{@color[2]}\n"\
					"      diffuse #{@color[0]} #{@color[1]} #{@color[2]}\n"\
					"      specular #{specular[0]} #{specular[1]} #{specular[2]} #{shininess}\n"\
					"      emissive 0.0 0.0 0.0\n"
		end
		

		if @textureName
			s.print	"      // texture size: #{@textureSize[0]}, #{@textureSize[1]}\n"\
					"      texture_unit\n"\
					"      {\n"\
					"        texture #{@textureName}\n"\
					"      }\n"
		end

		s.print	"    }\n"\
				"  }\n"\
				"}\n"
		
	end
	
end


# This class summarize the information about a face to be exported
class FaceInfo
	attr_reader :face, :trans, :front_side
	attr_writer :face, :trans, :front_side
	
	def initialize(f, t, s)
		@face = f
		@trans = t
		@front_side = s
	end
end

class MaterialInfo
	attr_reader :sketchup_material, :ogre_material, :front_side
	attr_writer :sketchup_material, :ogre_material, :front_side
	
	def initialize(skm, ogm, ff)
		@sketchup_material = skm
		@ogre_material = ogm
		@front_side = ff
	end
end

# If the entity (on the specified side) has a material, updates the provided maps and returns a MaterialInfo instance properly filled.
# Otherwise returns nil
def getMaterialInfo (e, front_side, mats_from_tex, mats_from_col)
	mat = nil
	if(front_side)
		mat = e.material
	else
		mat = e.back_material
	end
	
	# Going to retrieve or create an OgreMaterial for this SketchupMaterial
	if(mat!=nil)
		ogre_mat = nil
		
		if mats_from_col[mat]
			ogre_mat = mats_from_col[mat]
			debug_print "Material #{ogre_mat.name} was already created from a color\n"
		elsif mats_from_tex[mat]
			materials_vect = mats_from_tex[mat] # Since the material was already created, there is at least one element
				
			# assert materials_vect.size > 0
				
			debug_print "Material #{materials_vect[0].name} was already created from a texture\n"
			debug_print "Trying to load another texture for the same material...\n"
			handle = $g_ogre_texturewriter.load(e,front_side)
			if(handle!=0)
				debug_print "Loaded a texture for the existing material with handle=#{handle.to_s}\n"
				old_mat = materials_vect.find {|m| m.textureHandle == handle} # returns the first material that was already using the same handle, or nil
				if old_mat!=nil
					debug_print "Resusing existing material\n"
					ogre_mat = old_mat
				else
					debug_print "Creating new material for an existing texture variant\n"
					ogre_mat = OgreMaterial.new
					ogre_mat.name = mat.display_name
					ogre_mat.color = [ mat.color.red/255.0, mat.color.green/255.0, mat.color.blue/255.0,  mat.alpha ]
					ogre_mat.textureName = String.new(mat.texture.filename) # We copy it because later it might be modified
					ogre_mat.textureHandle = handle
					ogre_mat.textureSize = [ mat.texture.width, mat.texture.height ]
					ogre_mat.textureSource = e
					ogre_mat.textureSourceFaceFront = front_side
					ogre_mat.useAlpha = mat.use_alpha?
					ogre_mat.alpha = mat.alpha
						
					# Adds the new OgreMaterial to the vector of OgreMaterials created from the same mat
					materials_vect << ogre_mat
				end
					
			else
				msg = "WARNING! No loadable texture for a material that was created from a texture!!!\nConsider export as invalid and, please, submit a test case to developers of the exporter."
				print msg + "\n"
				UI.messagebox msg
			end
		else
			debug_print "Defining new OgreMaterial from material #{mat.name}... \n"
				
			handle = $g_ogre_texturewriter.load(e,front_side)
			debug_print "Handle for texture = #{handle} -> reaching " + $g_ogre_texturewriter.count.to_s + " textures\n"				
				
			if(handle==0) # This is a material without textures
				ogre_mat = OgreMaterial.new
				ogre_mat.name = mat.display_name
				ogre_mat.color = [ mat.color.red/255.0, mat.color.green/255.0, mat.color.blue/255.0,  mat.alpha ]
				ogre_mat.useAlpha = mat.use_alpha?
				ogre_mat.alpha = mat.alpha

				mats_from_col[mat] = ogre_mat
			else
				ogre_mat = OgreMaterial.new
				ogre_mat.name = mat.display_name
				ogre_mat.color = [ mat.color.red/255.0, mat.color.green/255.0, mat.color.blue/255.0,  mat.alpha ]
				ogre_mat.textureName = String.new(mat.texture.filename) # We copy it because it might be modified
				ogre_mat.textureHandle = handle
				ogre_mat.textureSize = [ mat.texture.width, mat.texture.height ]
				ogre_mat.textureSource = e
				ogre_mat.textureSourceFaceFront = front_side
				ogre_mat.useAlpha = mat.use_alpha?
				ogre_mat.alpha = mat.alpha
					
				mats_from_tex[mat] = [ogre_mat]
			end
				
		end

		# assert ogre_mat != nil # or a Warning message has been issued.

		return MaterialInfo.new(mat, ogre_mat, front_side)
		
	else
		return nil
	end

end

# This procedure recursively scan the model hierarchy and fills several structures with the collected data
# In Sketchup, the texture writer loads several copies of the same texture, appropriately scaled and rotated, when some kind of texture positioning is applied.
# We then classify OgreMaterials in two categories: from_texture and from_color.
# Given an entity, we try to load the textures it uses. If the texture writer returns 0, it uses no textures, otherwise, we memorize the handler and create a new OgreMaterial for each texture created.
#
# level The nesting level of the recursion
# entity_list an array of Entity to analyze
# trans a Transformation instance to be applied to all the listed entity
# parent_mat the inherited SketchUp::Material
# parent_ogre_mat the corresponding inherited OgreMaterial
# mats_from_tex The map collecting the materials created from textures
# mats_from_col The map collecting the materials created withtou texture
# faces_map The map collecting all the faces, divided according to the OgreMaterial they use.
# default_mat_faces an Array collecting the faces using the default material
# collect_back_faces Tells whether to scan also the back faces or not.
def ogre_scan_geometry(level, entity_list, trans, parent_mat, parent_ogre_mat, mats_from_tex, mats_from_col, faces_map, default_mat_faces, collect_back_faces)
	indent = "  " * level ;
	debug_print indent+level.to_s+"\n"

	#assert (parent_mat == nil and parent_ogre_mat == nil) or (parent_mat != nil and parent_ogre_mat != nil)
	
	for e in entity_list
	
		debug_print indent+"Found entity of class '#{e.class}'\n"
	
		#mat = parent_mat # reset material reference
		#ogre_mat = parent_ogre_mat # This will be left as it is, or created, or retrieved
		front_mat_info = MaterialInfo.new(parent_mat, parent_ogre_mat, true)
		back_mat_info = MaterialInfo.new(parent_mat, parent_ogre_mat, false)

		
		#  If  the entity is one of the accepted types, try to get its own material
		if (e.class == Sketchup::Face or e.class == Sketchup::ComponentInstance or e.class == Sketchup::Group)
		
			fmi = getMaterialInfo(e, true, mats_from_tex, mats_from_col)
			if(fmi != nil)
				front_mat_info = fmi
				debug_print "This entity has its own front material\n"
			else
				debug_print "Inheriting front material from parent\n"
			end

			# We scan also the back face only if the entity is a Face and it is required by the caller
			if (e.class == Sketchup::Face) and collect_back_faces
				bmi = getMaterialInfo(e, false, mats_from_tex, mats_from_col)
				if( bmi != nil)
					back_mat_info = bmi
					debug_print "This face has its own back material\n"
				else
					debug_print "Inheriting back material from parent\n"
				end
			end
			
		else
			debug_print "Untreated entity #{e} of class #{e.class}. Ignoring material.\n"
			#mat = nil 
			#ogre_mat = nil
		end

		#assert front_mat_info != nil and back_mat_info != nil
		#assert (front_mat_info.sketchup_material == nil and front_mat_info.ogre_material == nil) or (front_mat_info.sketchup_material != nil and front_mat_info.ogre_material != nil)
		#assert (back_mat_info.sketchup_material == nil and back_mat_info.ogre_material == nil) or (back_mat_info.sketchup_material != nil and back_mat_info.ogre_material != nil)
	
		# If the entity if a group, recurse in subgroups applying the transformation matrix.
		if e.class == Sketchup::Group
			ogre_scan_geometry(level+1, e.entities, trans*e.transformation, front_mat_info.sketchup_material, front_mat_info.ogre_material, mats_from_tex, mats_from_col, faces_map, default_mat_faces, collect_back_faces)
			
		elsif e.class == Sketchup::ComponentInstance 		# do the same if the entity is a ComponentInstance
			ogre_scan_geometry(level+1, e.definition.entities, trans*e.transformation, front_mat_info.sketchup_material, front_mat_info.ogre_material, mats_from_tex, mats_from_col, faces_map, default_mat_faces, collect_back_faces)
		elsif e.class == Sketchup::Face 		# if the entity is a face, add the information of the face to the map keeping the list of the faces using that material.

			mats = [front_mat_info]
			# if requested, we add also the material for the back face
			if collect_back_faces 
				mats << back_mat_info
			end

			mats.each { |mi|
				debug_print "mi=#{mi} #{mi.front_side}\n"
				ogre_mat = mi.ogre_material
				if ogre_mat!=nil

					# Adds the face to the set of faces used by this material
					debug_print "Adding face to OgreMaterial #{ogre_mat.name}\n"
					if faces_map[ogre_mat] == nil
						faces_map[ogre_mat] = []
					end
					faces_map[ogre_mat] << FaceInfo.new(e, trans, mi.front_side)
				
				else
					debug_print "No material found for a face. Assigning default.\n"
					default_mat_faces << FaceInfo.new(e,trans, mi.front_side)
				end
			}
		end
		
	end

end


# Export the faces of the model as ogre submeshes
# out is the stream to write to
# ogre_mat is an instance od OgreMaterial
# faces_data is an array of couples FaceInfo instances to export
def ogre_export_face(out, ogre_mat, faces_data)
	meshes = []
	polycount = 0
	pointcount = 0
	mirrored={}

	# In this cycle ft stands for "face transformed" with ft.face we access the Face entity, with ft.trans we access the transform
	for ft in (faces_data)
		polymesh = ft.face.mesh 7
		#polymesh.transform! ft[1] # The transform must be aplied to vertices, not to the whole polimesh
#		mirrored[polymesh] = true
#		xa = point_to_vector(ft.trans.xaxis)
#		ya = point_to_vector(ft.trans.yaxis)
#		za = point_to_vector(ft.trans.zaxis)
#		xy = xa.cross(ya)
#		xz = xa.cross(za)
#		yz = ya.cross(za)
#		if xy.dot(za) < 0
#			mirrored[polymesh] = !mirrored[polymesh]
#		end
#		if xz.dot(ya) < 0
#			mirrored[polymesh] = !mirrored[polymesh]
#		end
#		if yz.dot(xa) < 0
#			mirrored[polymesh] = !mirrored[polymesh]
#		end
		
		mirrored[polymesh] = ft.trans.xaxis.cross(ft.trans.yaxis).dot(ft.trans.zaxis) < 0
		#if mirrored[polymesh]
		#	print "Found a mirrored face = "+mirrored[polymesh].to_s+"\n"
		#end
		
		#[ 0: (PolyMesh) The polymesh obtained with Face.mesh 7
		#1: (Face) The Sketchup Face corresponding to this poligon
		#2: (Transformation) The Transformation applied to this poligon
		#3: (bool) true if exporting a front face, false for backs
		meshes << [ polymesh, ft.face, ft.trans, ft.front_side ]
		
		
		polycount=polycount + polymesh.count_polygons
		pointcount=pointcount + polymesh.count_points
	end

	startindex = 0
	has_texture = false
	if ogre_mat.textureName
		has_texture = true
	end

	out.print "      <submesh material = \"#{ogre_mat.name}\" usesharedvertices=\"false\" "
	if pointcount<65537 
		out.print "use32bitindexes=\"false\">\n"
	else
		out.print "use32bitindexes=\"true\">\n"
	end

	$g_ogre_count_submesh = $g_ogre_count_submesh + 1
	out.print "         <faces count=\"#{polycount}\">\n"
	for mesh in meshes
		for poly in mesh[0].polygons
			v1 = (poly[0]>=0?poly[0]:-poly[0])+startindex
			v2 = (poly[1]>=0?poly[1]:-poly[1])+startindex
			v3 = (poly[2]>=0?poly[2]:-poly[2])+startindex
			if mirrored[mesh[0]] == mesh[3] # if the mirroring corresponds to the front condition
				out.print "            <face v1=\"#{v2-1}\" v2=\"#{v1-1}\" v3=\"#{v3-1}\" />\n"
			else
				out.print "            <face v1=\"#{v1-1}\" v2=\"#{v2-1}\" v3=\"#{v3-1}\" />\n"
			end
			$g_ogre_count_tri = $g_ogre_count_tri + 1
		end
		startindex = startindex + mesh[0].count_points
	end
	out.print	"         </faces>\n"\
				"         <geometry vertexcount=\"#{pointcount}\">\n"\
				"            <vertexbuffer positions=\"true\" normals=\"true\" colours_diffuse=\"false\" "
	if has_texture 
		out.print "texture_coords=\"1\" texture_coord_dimensions_0=\"2\""
	end
	out.print " >\n"
	
	for mesh in meshes
		matrix = mesh[2]
		#debug_print "Matrix is: " + transform_to_s(matrix)
		$g_test = mesh
		for p in (1..mesh[0].count_points)
			pos = (matrix*mesh[0].point_at(p)).to_a
			norm = (matrix*mesh[0].normal_at(p)).normalize.to_a
			out.print	"               <vertex>\n"\
						"                  <position x=\"#{pos[0]*$g_ogre_scale}\" y=\"#{pos[2]*$g_ogre_scale}\" z=\"#{pos[1]*-$g_ogre_scale}\" />\n"
			if mesh[3] # if it is the front
				out.print	"                  <normal x=\"#{norm[0]}\" y=\"#{norm[2]}\" z=\"#{-norm[1]}\" />\n"
			else
				out.print	"                  <normal x=\"#{-norm[0]}\" y=\"#{-norm[2]}\" z=\"#{norm[1]}\" />\n"
			end

			if has_texture 
				# if the entity was not defining its own material, the texture coordinates must be adapted using the original size of the texture
				if (mesh[3] and (mesh[1].material == nil)) or ((not mesh[3]) and (mesh[1].back_material == nil))
					texsize = Geom::Point3d.new(ogre_mat.textureSize[0], ogre_mat.textureSize[1], 1)
					debug_print "->> Using texture size from texture: #{texsize}\n"
				else
					texsize = Geom::Point3d.new(1,1,1)
					debug_print "->> Using texsize as default: #{texsize}\n"
				end
				uvhelp = mesh[1].get_UVHelper true, true, $g_ogre_texturewriter
				if mesh[3] # if it is the front
					uv3d = uvhelp.get_front_UVQ mesh[0].point_at(p)
				else
					uv3d = uvhelp.get_back_UVQ mesh[0].point_at(p)				
				end
			
				out.print "                  <texcoord u=\"#{uv3d[0]/texsize.x}\" v=\"#{-uv3d[1]/texsize.y+1}\" />\n"
				
			end
			out.print "               </vertex>\n"
		end
	end
	out.print	"            </vertexbuffer>\n"\
				"         </geometry>\n"\
				"      </submesh>\n"
end


# The main export procedure, called by menu selection.
def ogre_export_selected
	$g_ogre_scale = 0.0254
	$g_ogre_count_submesh = 0
	$g_ogre_count_tri = 0

	# re-load the config at each call.
	load "ogre_export_config.rb"

	
	# (SketchUp::Material)key, (Array) data.
	# The data is an array  of (OgreMaterial). All the Ogre materials are built loading the same texture that returned a different handle
	materials_from_textures = {}

	# (SketchUp::Material)key, (OgreMaterial)data
	materials_from_colors = {}
	
	default_material = OgreMaterial.new
	default_material.name = "SketchupDefault"
	default_material.color = [0.8,0.8, 0.8]
	default_material.useAlpha = false ;
	
	# (OgreMaterial)key, (Array) data = an array of FaceInfo instances
	faces_map = {}

	# Each element is FaceInfo instance
	faces_with_default_material = []

	
	$g_ogre_texturewriter = Sketchup.create_texture_writer
	$g_ogre_export_name = ""

	#
	# Ask export name
	#
	temp_name = (UI.inputbox ["Export Name"],[$g_ogre_export_name],"Export To Ogre")
	if temp_name == false
		return
	end
	$g_ogre_export_name = temp_name[0]
	if $g_ogre_export_name == ""
		return
	end


	#
	# Scan geometry
	# For the selected scene, analyze the entities and retrieve the names of the used materials
	#
	puts "Scanning geometry...\n"
	ents = []
	
	
	
	Sketchup.active_model.selection.each{|e| ents = ents + [e]}
    
    
    
    
	ogre_scan_geometry(0, ents, Geom::Transformation.new, nil, nil, materials_from_textures, materials_from_colors, faces_map, faces_with_default_material, $ogre_export_backfaces)

	puts materials_from_colors.size.to_s + " sketchup materials from colors.\n"
	puts materials_from_textures.size.to_s + " sketchup materials from textures.\n"
	materials_from_textures.keys.each { |mat|
		ogre_mats = materials_from_textures[mat]
		puts "    " + ogre_mats.size.to_s + " texture variants for material #{mat.name}\n"
	}
		
	puts "Total ogre materials associated to faces: #{faces_map.keys.size.to_s}\n"

	
	#
	# Name uniqueness
	#
	prefix = Time.now.to_i.to_s ;


	# Adjust the name for all materials
	mat_id = 1
	faces_map.keys.each { |mat|
		debug_print "Change material name from '#{mat.name}' to "
		# Removes spaces from material name
		mat.name.gsub!(/ /, '_')
		
		mat.name = mat_id.to_s + "_" + mat.name
		
		if $g_ogre_append_unique_prefix
			mat.name = prefix + "_" + mat.name
		end
		
		debug_print "'#{mat.name}'\n"
		
		mat_id = mat_id + 1 
	}
	
	# adjust the name for all textures
	tex_id = 1 # Used to ensure texture name uniqueness. Needed because TextureWriter.filename doesn't work.
	materials_from_textures.values.each { |mat_vect|
		mat_vect.each { |mat|
			debug_print "Change texture name from '#{mat.textureName}' to "

			# Removes spaces
			mat.textureName.gsub!(/ /, '_')

			# Removes slashes and backslashes from texture names
			cleanname = ""
			mat.textureName.each("\\") {|n| cleanname = n}
			mat.textureName = cleanname ;
			mat.textureName.each("/") {|n| cleanname = n}
			mat.textureName = cleanname ;
			# Ensure name uniqueness
			mat.textureName = tex_id.to_s + "_" + mat.textureName

			if $g_ogre_append_unique_prefix
				mat.textureName = prefix + "_" + mat.textureName
			end

			debug_print "'#{mat.textureName}'\n"
			
			tex_id = tex_id + 1		
		}
	}
	
	
	#
	# Write geometry
	#
	if $g_ogre_export_meshes
		puts "Exporting meshes...\n"
		file_mesh_xml = open(append_paths($g_ogre_path_meshes,$g_ogre_export_name+".mesh.xml"),"w")
		file_mesh_xml.print "<mesh>\n"
		file_mesh_xml.print "   <submeshes>\n"

		# For each material in the system, if it is used by some entity (i.e. inserted in faces_map before)  then export its faces as submesh.
		faces_map.keys.each { |mat|
			faces_data = faces_map[mat]
			if(faces_data)
				debug_print "Exporting #{faces_data.size} faces for material #{mat.name}\n"
				ogre_export_face(file_mesh_xml, mat, faces_data)
			else
				print "WARNING!!! No faces for registered material #{mat.name}!\n"
			end
		}

		if faces_with_default_material.size > 0
			debug_print "Exporting #{faces_with_default_material.size} mesh with default material...\n"
			ogre_export_face(file_mesh_xml, default_material, faces_with_default_material)
		end

		file_mesh_xml.print "   </submeshes>\n"
		file_mesh_xml.print "</mesh>\n"
		file_mesh_xml.close
	end
	
	
	#
	# Write materials
	#
	if $g_ogre_export_materials
		puts "Writing materials...\n"
		
		file_material = open(append_paths($g_ogre_path_materials,$g_ogre_export_name+".material"),"w")

		faces_map.keys.each { |mat|
			mat.writeOut file_material
		}

		if($g_ogre_export_default_material)
			puts "Exporting default material '#{default_material.name}'\n" 
			default_material.writeOut file_material
		end
	
		file_material.close
	end
	
	# Write Textures
	if $g_ogre_copy_textures
		puts "Writing textures...\n"
		failed_textures = []
		# TODO - save only textures for materials used by some face
		materials_from_textures.values.each { |mat_vect|
			
			mat_vect.each { |mat|
				if faces_map.include? mat 
			
					# assert mat.textureName != nil
					
					# This doesn't work!!! - file_name = $g_ogre_texturewriter.filename mat.textureHandle
					# print "Should write a texture named '#{file_name}'\n"
					puts "Writing texture '#{mat.textureName}' for material #{mat.name}. Source type was #{mat.textureSource.class.to_s}. useAlpha reported #{mat.useAlpha}.\n"
					write_result = 0
					if(mat.textureSource.class == Sketchup::Face)
						write_result = $g_ogre_texturewriter.write(mat.textureSource, mat.textureSourceFaceFront, append_paths($g_ogre_path_textures, mat.textureName))
					else
						write_result = $g_ogre_texturewriter.write(mat.textureSource, append_paths($g_ogre_path_textures, mat.textureName))
					end
					if write_result == 0
						puts "FILE_WRITE_OK.\n"
					elsif write_result == 1
						puts "FILE_WRITE_FAILED_INVALID_TIFF\n"
						failed_textures << mat.textureName
					elsif write_result == 2
						puts "FILE_WRITE_FAILED_UNKNOWN\n"
						failed_textures << mat.textureName
					else
						puts "Unknown write result '#{write_result}'!!! Update your code!\n"
						failed_textures << mat.textureName
					end
				else
					puts "Skipping texture write for unused material #{mat.name}\n"
				end
			}
		}
		
		if failed_textures.size > 0
			msg = "Failed to write the following textures:\n" + failed_textures.inject("") { |total, t| total + t + "\n" }
			puts msg
			UI.messagebox msg
		end
		
	end
	
	
	# Info to user
	UI.messagebox "Triangles = #{$g_ogre_count_tri}\nSubmeshes/Materials = #{$g_ogre_count_submesh}"

	if $g_ogre_convert_xml == true
		puts "Converting into binary mesh...\n"
		system($g_ogre_path_xml_converter + " " + append_paths($g_ogre_path_meshes,$g_ogre_export_name+".mesh.xml"))
	end

	puts "Export finished.\n"
end


menu = UI.menu "Tools";
menu.add_separator
menu.add_item( "Export Selection to Ogre Mesh") {ogre_export_selected}
