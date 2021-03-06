{-# LANGUAGE QuasiQuotes, FlexibleContexts #-}

import Data.Array.Repa (Z (..), (:.) (..), D, DIM2, Array, (!))
import qualified Data.Array.Repa                 as R

import Data.Array.Accelerate.IO
import Data.Array.Accelerate ((==*), (<*), (>*), (||*), Acc, Exp, (?))
import qualified Data.Array.Accelerate           as A
import qualified Data.Array.Accelerate.CUDA      as C

import Graphics.Gloss
import Graphics.Gloss.Raster.Array
import Graphics.Gloss.Interface.Pure.Game

type Life = Int
type Coord = (Float, Float)
type Matrix x = A.Array A.DIM2 x

data World = World { arr :: Array A DIM2 Life
                   , mouseDown :: Bool
                   , mousePos  :: Coord }

conwayStencil :: Acc (Matrix Life) -> Acc (Matrix Life)
conwayStencil = A.stencil f A.Clamp
  where f :: A.Stencil3x3 Life -> Exp Life
        f ((x00,x01,x02)
          ,(x10,x11,x12)
          ,(x20,x21,x22)) = x00 + x01 + x02 + x10 + x12 + x20 + x21 + x22

delta :: Exp Life -> Exp Int -> Exp Life
delta x n = (x ==* 1) ? ( (n <* 2 ||* n >* 3) ? (0, 1)
                        , (n ==* 3)           ? (1, 0))

tick :: Acc (Matrix Life) -> Acc (Matrix Life)
tick a = A.zipWith delta a $ conwayStencil a

resX = 640
resY = 480

step :: Monad m => Float -> World -> m World
step time world
 = let updateMouse = if mouseDown world
                     then updatePoint (mousePos world) 1
                     else return
   in  do w' <- updateMouse (arr world)
          return $ world { arr = toRepa $ C.run $ tick $ A.lift $ fromRepa w' }

stepWorld :: [(Element, R.Array R.V  R.DIM2 Color)] -> Float -> World -> IO World
stepWorld tooltips time world
 = let curr = mousePos world
       world' = if outOfWorld curr then handleUI tooltips curr world else world { tooltipRight = blankTooltip }
   in  do int     <- randomRIO (0,100)
          stepped <- if   mouseDown world
                     then liftM (step int $ currGravityMask world')
                             $  drawLineA (mousePrevPos world') curr
                                          (currentElem  world') (array world')
                     else return $ step int (currGravityMask world')
                                 $ array world'
          array'  <- R.computeP stepped
          return $ world' { array = array'
                          , currGravityMask = nextGravityMask world'
                          , nextGravityMask = currGravityMask world' }

updatePoint :: Monad m => Coord -> Life -> Array A DIM2 Life -> m (Array A DIM2 Life)
updatePoint (x,y) newLife arr
 = let same a a' n = abs (round a + (n `div` 2) - a') < 5
   in  computeAccP $ R.fromFunction (Z :. resY :. resX)
              (\sh@(Z :. y' :. x')
                -> if same x x' resX && same y y' resY
                   then newLife
                   else arr ! sh)

render :: World -> Array D DIM2 Color
render world = R.map color $ arr world
  where color 0 = black
        color _ = white

main :: IO ()
main = do
  tooltips <- mapM loadTooltip tooltipFiles
  playArrayIO
    (InWindow "Falling Turnip" (winX * round factor, winY * round factor) (pos, pos))
    (round factor, round factor)
    frameRate
    (World { array = R.computeS $ R.fromFunction (Z :. resY :. resX) bareWorld
           , currentElem     = nothing
           , currGravityMask = margMaskEven
           , nextGravityMask = margMaskOdd
           , mouseDown       = False
           , mousePos        = (0,0)
           , mousePrevPos    = (0,0)
           , tooltipLeft     = blankTooltip
           , tooltipRight    = blankTooltip
           })
    ( return    . render)
    ((return .) . handleInput)
    (stepWorld tooltips)
  where frameRate = 30
        pos       = 300
        bareWorld = const nothing

loadTooltip :: (Element, FilePath) -> IO (Element, R.Array R.V R.DIM2 Color)
loadTooltip (e, p) = getDataFileName p >>= \p' -> liftM ((e,) . either (error) fromJuicy) $ J.readImageRGBA p'
  where toF :: Word8 -> Float
        toF x = fromIntegral x / 255
        fromJuicy :: J.Collapsable a (Word8, Word8, Word8, Word8) => J.Img a -> R.Array R.V R.DIM2 Color
        fromJuicy = (R.computeS . flip . R.map (\(a,b,c,d) -> makeColor (toF b) (toF c) (toF d) (toF a) ) . J.collapseColorChannel)
        flip = R.backpermute (Z :. 15 :. 160) (\(Z:. y :. x) -> Z :. (14 - y) :. x )

handleInput :: Event -> World -> World
handleInput e w = handleInput' (w {mousePrevPos = mousePos w})
  where handleInput' world = case e of
          EventKey (MouseButton LeftButton) Down _ (x,y) -> world { mouseDown = True, mousePos = (x/factor, y/factor - palletteH) }
          EventKey (MouseButton LeftButton) Up _   (x,y) -> world { mouseDown = False, mousePos = (x/factor, y/factor - palletteH) }
          EventKey (Char 'e') Down _ _ -> world { currentElem = steam_water }
          EventKey (Char 'f') Down _ _ -> world { currentElem = fire        }
          EventKey (Char 'o') Down _ _ -> world { currentElem = oil         }
          EventKey (Char 'w') Down _ _ -> world { currentElem = water       }
          EventKey (Char 'l') Down _ _ -> world { currentElem = salt_water  }
          EventKey (Char 's') Down _ _ -> world { currentElem = sand        }
          EventKey (Char 'n') Down _ _ -> world { currentElem = salt        }
          EventKey (Char 't') Down _ _ -> world { currentElem = stone       }
          EventKey (Char 'r') Down _ _ -> world { currentElem = torch       }
          EventKey (Char 'a') Down _ _ -> world { currentElem = wall        }
          EventKey (Char 'p') Down _ _ -> world { currentElem = plant       }
          EventKey (Char 'u') Down _ _ -> world { currentElem = spout       }
          EventKey (Char 'm') Down _ _ -> world { currentElem = metal       }
          EventMotion (x,y) -> world { mousePos = (x/factor, y/factor - palletteH) }
          _ -> world

blankTooltip :: R.Array R.V R.DIM2 Color
blankTooltip = R.computeS $ R.fromFunction (Z :. 15 :. 160) (const black)

handleUI :: [(Element, R.Array R.V R.DIM2 Color)] -> GlossCoord -> World -> World
handleUI t p w = let tooltip = fromMaybe blankTooltip $ flip lookup t $ elemOf p
                 in if mouseDown w then
                     w {currentElem = elemOf p, tooltipLeft = tooltip
                                              , tooltipRight = tooltip }
                    else w { tooltipRight = tooltip }

