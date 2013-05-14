# distutils: language = c++
# distutils: sources = vpp.cpp
# 
# voroplusplus.pyx : pyvoro cython interface to voro++
#
# this file provides a python interface for performing 3D voronoi tesselations
# using voro++.
#
# this extension to voro++ is released under the original modified BSD license
# and constitutes an Extension to the original project.
#
# Copyright (c) Joe Jordan 2012
# contact: <joe.jordan@imperial.ac.uk> or <tehwalrus@h2j9k.org>
#

from libcpp.vector cimport vector
from cython.operator cimport dereference as deref

cdef extern from "vpp.h":
  void* container_create(double ax_, double bx_, double ay_, double by_,
    double az_, double bz_, int nx_, int ny_, int nz_)
  void put_particle(void* container_, int i_, double x_, double y_, double z_)
  void put_particles(void* container_, int n_, double* x_, double* y_, double* z_)
  void** compute_voronoi_tesselation(void* container_, int n_)
  double cell_get_volume(void* cell_)
  vector[double] cell_get_vertex_positions(void* cell_, double x_, double y_, double z_)
  void** cell_get_vertex_adjacency(void* cell_)
  void** cell_get_faces(void* cell_)
  void dispose_all(void* container_, void** vorocells, int n_)


cdef extern from "stdlib.h":
  ctypedef unsigned long size_t
  void free(void *ptr)
  void* malloc(size_t size)

import math

class VoronoiPlusPlusError(Exception):
  pass

def compute_voronoi(points, limits, dispersion):
  """
Input arg formats:
  points = list of 3-vectors (lists or compatible class instances) of doubles,
    being the coordinates of the points to voronoi-tesselate.
  limits = 3-list of 2-lists, specifying the start and end sizes of the box the
    points are in.
  dispersion = max distance between two points that might be adjacent (sets
    voro++ block sizes.)
  
Output format is a list of cells as follows:
  [ # list in same order as original points.
    {
      'volume' : 1.0,
      'vetices' : [[1.0, 2.0, 3.0], ...], # positions of vertices
      'adjacency' : [[1,3,4, ...], ...], # cell-vertices adjacent to i by index
      'faces' : [
        {
          'vertices' : [7,4,13, ...], # vertex ids in loop order
          'adjacent_cell' : 34 # *cell* id, negative if a wall
        }, ...]
      'original' : point[index] # the original instance from args
    },
    ... 
  ]
  
  NOTE: The class from items in input points list is reused for all 3-vector
  outputs. It must have a contructor which accepts a list of 3 python floats
  (python's list type does satisfy this requirement.)
  """
  cdef int n = len(points), i, j
  cdef double *xs, *ys, *zs
  cdef void** voronoi_cells
  vector_class = points[0].__class__
  
  # we must make sure we have at least one block, or voro++ will segfault when
  # we look for cells.
  
  blocks = [
    max([1, int(math.floor((limits[0][1] - limits[0][0]) / dispersion))]),
    max([1, int(math.floor((limits[1][1] - limits[1][0]) / dispersion))]),
    max([1, int(math.floor((limits[2][1] - limits[2][0]) / dispersion))])
  ]
  
  # build the container object
  cdef void* container = container_create(
    <double>limits[0][0],
    <double>limits[0][1],
    <double>limits[1][0],
    <double>limits[1][1],
    <double>limits[2][0],
    <double>limits[2][1],
    <int>blocks[0],
    <int>blocks[1],
    <int>blocks[2]
  )
  
  xs = <double*>malloc(sizeof(double) * n)
  ys = <double*>malloc(sizeof(double) * n)
  zs = <double*>malloc(sizeof(double) * n)
  
  # initialise particle positions:
  for i from 0 <= i < n:
    xs[i] = <double>points[i][0]
    ys[i] = <double>points[i][1]
    zs[i] = <double>points[i][2]
  
  # and add them to the container:
  put_particles(container, n, xs, ys, zs)
  
  # now compute the tessellation:
  voronoi_cells = compute_voronoi_tesselation(container, n)
  
  if voronoi_cells == NULL:
    dispose_all(container, NULL, 0)
    raise VoronoiPlusPlusError("number of cells found was not equal to the number of particles.")
  
  # extract the Voronoi cells into python objects:
  py_cells = [{'original':p} for p in points]
  cdef vector[double] vertex_positions
  cdef void** lists = NULL
  cdef vector[int]* vptr = NULL
  for i from 0 <= i < n:
    py_cells[i]['volume'] = float(cell_get_volume(voronoi_cells[i]))
    vertex_positions = cell_get_vertex_positions(voronoi_cells[i], xs[i], ys[i], zs[i])
    cell_vertices = []
    for j from 0 <= j < vertex_positions.size() / 3:
      cell_vertices.append(vector_class([
        float(vertex_positions[3 * j]),
        float(vertex_positions[3 * j + 1]),
        float(vertex_positions[3 * j + 2])
      ]))
    py_cells[i]['vertices'] = cell_vertices
    
    lists = cell_get_vertex_adjacency(voronoi_cells[i])
    adjacency = []
    j = 0
    while lists[j] != NULL:
      py_vertex_adjacency = []
      vptr = <vector[int]*>lists[j]
      for k from 0 <= k < vptr.size():
        py_vertex_adjacency.append(int(deref(vptr)[k]))
      del vptr
      adjacency.append(py_vertex_adjacency)
      j += 1
    free(lists)
    py_cells[i]['adjacency'] = adjacency
    
    lists = cell_get_faces(voronoi_cells[i])
    faces = []
    j = 0
    while lists[j] != NULL:
      face_vertices = []
      vptr = <vector[int]*>lists[j]
      for k from 0 <= k < vptr.size() - 1:
        face_vertices.append(int(deref(vptr)[k]))
      faces.append({
        'adjacent_cell' : int(deref(vptr)[vptr.size() - 1]),
        'vertices' : face_vertices
      })
      del vptr
      j += 1
    free(lists)
    py_cells[i]['faces'] = faces
  
  # finally, tidy up.
  dispose_all(container, voronoi_cells, n)
  free(xs)
  free(ys)
  free(zs)
  return py_cells

