package;

import flixel.FlxStrip;
import nape.geom.AABB;
import nape.geom.MarchingSquares;
import nape.geom.Vec2;
import nape.phys.BodyType;
import nape.shape.Polygon;
import nape.space.Space;
import openfl.display.BitmapData;
import nape.phys.Body;

class Terrain #if flash implements nape.geom.IsoFunction #end 
{
	private var cellSize:Float;
	private var subSize:Float;
	
	private var width:Int;
	private var height:Int;
	private var cells:Array<Body>;
	
	private var isoBounds:AABB;
	
	public var bitmap:BitmapData;
	public var isoGranularity:Vec2;
	public var isoQuality:Int = 8;
	// TODO: store several strips (one for each cell)
	public var strip:FlxStrip;
	
	public function new(bitmap:BitmapData, cellSize:Float, subSize:Float) 
	{
		this.bitmap = bitmap;
		this.cellSize = cellSize;
		this.subSize = subSize;
		
		cells = [];
		width = Math.ceil(bitmap.width / cellSize);
		height = Math.ceil(bitmap.height / cellSize);
		for (i in 0...(width * height)) cells.push(null);
		
		isoBounds = new AABB(0, 0, cellSize, cellSize);
		isoGranularity = Vec2.get(subSize, subSize);
		
		strip = new FlxStrip(0, 0, "assets/Patagonia30.jpg");
	}
	
	public function invalidate(region:AABB, space:Space) 
	{
		// compute effected cells.
		var x0 = Std.int(region.min.x / cellSize); if (x0 < 0) x0 = 0;
		var y0 = Std.int(region.min.y / cellSize); if (y0 < 0) y0 = 0;
		var x1 = Std.int(region.max.x / cellSize); if (x1 >= width) x1 = width - 1;
		var y1 = Std.int(region.max.y / cellSize); if (y1 >= height) y1 = height - 1;
		
		var sweepContexts:Array<org.poly2tri.SweepContext> = [];
		var points:Array<org.poly2tri.Point> = [];
		
		for (y in y0...(y1 + 1)) 
		{
			for (x in x0...(x1 + 1)) 
			{
				var b = cells[y * width + x];
				if (b != null) 
				{
					// If body exists, we'll simply re-use it.
					b.space = null;
					b.shapes.clear();
				}
				
				isoBounds.x = x * cellSize;
				isoBounds.y = y * cellSize;
				var polys = MarchingSquares.run(
					#if flash this #else this.iso #end,
					isoBounds,
					isoGranularity,
					isoQuality
				);
				
				if (polys.empty()) continue;
				
				if (b == null) 
				{
					cells[y * width + x] = b = new Body(BodyType.STATIC);
				}
				
				for (p in polys) 
				{
					var qolys = p.convexDecomposition(true);
					for (q in qolys) {
						b.shapes.add(new Polygon(q));
						// Recycle GeomPoly and its vertices
						q.dispose();
					}
					
					// Recycle list nodes
					qolys.clear();
					// Recycle GeomPoly and its vertices
					p.dispose();
				}
				
				// Recycle list nodes
				polys.clear();
				
				b.space = space;
				
				for (shape in b.shapes)
				{
					if (Std.is(shape, Polygon))
					{
						var poly:Polygon = cast(shape, Polygon);
						
						var context = new org.poly2tri.SweepContext();
						points = [];
						
						for (v in poly.worldVerts)
						{
							points.push(new org.poly2tri.Point(v.x, v.y));
						}
						
						context.addPolyline(points);
						sweepContexts.push(context);
					}
				}
			}
		}
		
		var vertices = strip.vertices;
		var ids = strip.indices;
		var uvs = strip.uvs;
		
		vertices.splice(0, vertices.length);
		ids.splice(0, ids.length);
		uvs.splice(0, uvs.length);
		
		var context:org.poly2tri.SweepContext;
		var triangle:org.poly2tri.Triangle;
		var pl:Array<org.poly2tri.Point>;
		var sweep:org.poly2tri.Sweep;
		var i:Int = 0;
		
		for (context in sweepContexts)
		{
			sweep = new org.poly2tri.Sweep(context);
			sweep.triangulate();
			
			var x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float;
			var maxX:Float, maxY:Float;
			var u:Float, v:Float;
			
			for (triangle in context.triangles)
			{
				pl = triangle.points;
				
				vertices.push(x1 = pl[0].x);
				vertices.push(y1 = pl[0].y);
				
				ids.push(i++);
				
				vertices.push(x2 = pl[1].x);
				vertices.push(y2 = pl[1].y);
				
				ids.push(i++);
				
				vertices.push(x3 = pl[2].x);
				vertices.push(y3 = pl[2].y);
				
				ids.push(i++);
				
				maxX = Math.max(x1, Math.max(x2, x3));
				maxY = Math.max(y1, Math.max(y2, y3));
				
				u = (pl[0].x % cellSize) / cellSize;
				v = (pl[0].y % cellSize) / cellSize;
				
				u = (u == 0 && pl[0].x == maxX) ? 1 : u;
				v = (v == 0 && pl[0].y == maxY) ? 1 : v;
				
				uvs.push(u);
				uvs.push(v);
				
				u = (pl[1].x % cellSize) / cellSize;
				v = (pl[1].y % cellSize) / cellSize;
				
				u = (u == 0 && pl[1].x == maxX) ? 1 : u;
				v = (v == 0 && pl[1].y == maxY) ? 1 : v;
				
				uvs.push(u);
				uvs.push(v);
				
				u = (pl[2].x % cellSize) / cellSize;
				v = (pl[2].y % cellSize) / cellSize;
				
				u = (u == 0 && pl[2].x == maxX) ? 1 : u;
				v = (v == 0 && pl[2].y == maxY) ? 1 : v;
				
				uvs.push(u);
				uvs.push(v);
			}
		}
	}
	 
	//iso-function for terrain, computed as a linearly-interpolated
	//alpha threshold from bitmap.
	public function iso(x:Float,y:Float):Float {
		var ix = Std.int(x); if(ix<0) ix = 0; else if(ix>=bitmap.width) ix = bitmap.width -1;
		var iy = Std.int(y); if(iy<0) iy = 0; else if(iy>=bitmap.height) iy = bitmap.height-1;
		var fx = x - ix; if(fx<0) fx = 0; else if(fx>1) fx = 1;
		var fy = y - iy; if(fy<0) fy = 0; else if(fy>1) fy = 1;
		var gx = 1-fx;
		var gy = 1-fy;
		 
		var a00 = bitmap.getPixel32(ix,iy)>>>24;
		var a01 = bitmap.getPixel32(ix,iy+1)>>>24;
		var a10 = bitmap.getPixel32(ix+1,iy)>>>24;
		var a11 = bitmap.getPixel32(ix+1,iy+1)>>>24;
		 
		var ret = gx * gy * a00 + fx * gy * a10 + gx * fy * a01 + fx * fy * a11;
		return 0x80 - ret;
	}
}