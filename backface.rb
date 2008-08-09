# Sketchup Backface Highlighting Version 1.0.0
# Written by Kojack
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

def iterate_for_backfaces(mat, entity_list)
	for e in entity_list
		if e.class == Sketchup::Group
			iterate_for_backfaces(mat, e.entities)
		end
		if e.class == Sketchup::ComponentInstance
			if $g_backfaces_instances[e.definition] == nil or mat == nil
				$g_backfaces_instances[e.definition] = true
				iterate_for_backfaces(mat, e.definition.entities)
			end
		end
		if e.class == Sketchup::Face
			if mat==nil
				if e.material == Sketchup.active_model.materials["Backfaces"]
					e.material = $g_backfaces[e]
				end
				if e.back_material == Sketchup.active_model.materials["Backfaces"]
					e.back_material = $g_backfaces[e]
				end
			else
				$g_backfaces[e]=e.back_material
				e.back_material = mat
			end
		end
	end
end

def highlight_backfaces
	$g_backfaces = {}
	$g_backfaces_instances = {}
	mat = Sketchup.active_model.materials["Backfaces"]
	if mat == nil
		mat = Sketchup.active_model.materials.add "Backfaces"
	end
	mat.color=[255,48,200]
	mat.texture = nil
	iterate_for_backfaces(mat,Sketchup.active_model.entities)
end

def unhighlight_backfaces
	if $g_backfaces.size>0
		iterate_for_backfaces(nil,Sketchup.active_model.entities)
		$g_backfaces = {}
		$g_backfaces_instances = {}
	end
end

def restore_backface_flip(e)
	if e.class == Sketchup::Face
		e.reverse!
		if e.material == Sketchup.active_model.materials["Backfaces"]
			e.material = $g_backfaces[e]
		end
		if e.back_material == Sketchup.active_model.materials["Backfaces"]
			e.back_material = $g_backfaces[e]
		end
		$g_backfaces.delete e
		temp = e.back_material
		e.back_material = e.material
		e.material = temp
	end
end

def unhighlight_flip_backface
	Sketchup.active_model.selection.each{|e| restore_backface_flip(e)}
end

menu = UI.menu "Tools";
menu.add_separator
menu.add_item( "Highlight Backfaces") {highlight_backfaces}
menu.add_item( "Unhighlight Backfaces") {unhighlight_backfaces}
menu.add_item( "Flip Backface") {unhighlight_flip_backface}
