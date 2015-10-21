import UIKit
import SDWebImage

// OK, so. This is based on CollectionViewContainerViewController 
// from the UIKitCatalogue example code from Apple.
// The technique is to use a collectionview which hosts another collectionview

class ShowsOverviewViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {

    private static let minimumEdgePadding = CGFloat(90.0)
    private var emitters:[ShowEmitter]!
    private let locationsHost = LocationsHost()!
    var cachedShows:[Show] = []
    private var currentShow: Show?

    private let leadingEdgeImageCache = SDWebImagePrefetcher()
    private let currentRowImageCache = SDWebImagePrefetcher()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let appVC = self.appViewController else { return print("you need an app VC") }
        guard let collectionView = collectionView else { return }

//        appVC.openShowWithID("joshua-liner-gallery-libby-black-theres-no-place-like-home")
//        appVC.presentShowViewControllerForShow(Show.stubbedShow())

        let network = appVC.context.network

        // Create an emitter for grabbing our Featured Shows
        // if the cache took longer than the slideshow, get it

        let featuredEmitter = FeaturedShowEmitter(title: "Featured Shows", initialShows: cachedShows, network: network)
        if cachedShows.isEmpty { featuredEmitter.getShows() }

        let otherEmitters:[ShowEmitter] = locationsHost.featured.map { locationID in
            return LocationBasedShowEmitter(location: locationsHost[locationID]!, network: network)
        }

        let featured:[ShowEmitter] = [featuredEmitter]
        emitters = featured + otherEmitters
        collectionView.reloadData()

        // Get the above the fold content
        requestShowsAtIndex(1)

        // Start listening for recommendations on when to cache, see the AppDelegate for more info
        NSNotificationCenter.defaultCenter().addObserver(self, selector:"remoteDidStopMoving", name:"stopped scroll", object:nil)
    }

    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        guard let nav = navigationController else { return }
        nav.viewControllers = nav.viewControllers.filter({ $0.isKindOfClass(AuthViewController) == false })
    }

    // Mark: Being too fancy?

    func remoteDidStopMoving() {
        delay(0.1) {
            guard let focalView = UIScreen.mainScreen().focusedView as? ShowCollectionViewCell else { return }
            guard let locationCell = focalView.superview?.superview?.superview as? ShowSetCollectionViewCell
                else { return print("View Heriarchy has changed for the ShowSetCollectionViewCell") }

            guard let locationIndexPath = self.collectionView?.indexPathForCell(locationCell)
                else { return print("Could not find indexpath for cell") }

            guard let showIndexPath = locationCell.collectionView.indexPathForCell(focalView)
                else { return print("Could not find indexpath for focal cell") }

            guard let emitter = self.locationEmitterAtIndex(locationIndexPath.section)
                else { return print("Could not find emitter for show set cell") }

            let show = emitter.showAtIndexPath(showIndexPath)
        }
    }

    // Mark: Getting locations

    func locationEmitterAtIndex(index: Int) -> LocationBasedShowEmitter? {

        // ignore the FeaturedShowEmitter
        if index == 0 || index > emitters.count - 1 { return nil }
        let anEmitter = emitters[index]
        guard let emitter = anEmitter as? LocationBasedShowEmitter else { return nil }
        return emitter
    }

    func requestShowsAtIndex(index: Int) {
        guard let emitter = locationEmitterAtIndex(index) else { return }
        emitter.getShows()
    }

    func precacheShowImagesAtIndex(index:Int) {
        guard let emitter = locationEmitterAtIndex(index) else { return }
        currentRowImageCache.cancelPrefetching()
        currentRowImageCache.prefetchURLs( emitter.imageURLsForShowsAtLocation() )
    }

    // Mark: Show Selection

    func showTapped(show: Show) {
        // can't pass the show as a sender - it has to be an object
        currentShow = show
        performSegueWithIdentifier("show", sender: self)
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        leadingEdgeImageCache.cancelPrefetching()
        currentRowImageCache.cancelPrefetching()

        if let locationsVC = segue.destinationViewController as? ShowViewController {
            locationsVC.show = currentShow
        }
    }
}



// All the collection view gubbins

extension ShowsOverviewViewController {

    // MARK: UICollectionViewDataSource

    override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return emitters.count
    }

    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {

        return collectionView.dequeueReusableCellWithReuseIdentifier(ShowSetCollectionViewCell.reuseIdentifier, forIndexPath: indexPath)
    }

    override func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        return collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: "header", forIndexPath: indexPath)
    }

    // MARK: UICollectionViewDelegateFlowLayout

    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if section != 0  { return CGSizeZero }
        return CGSizeMake(view.bounds.width, 180)
    }

    // MARK: UICollectionViewDelegate

    override func collectionView(collectionView: UICollectionView, willDisplayCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        guard let cell = cell as? ShowSetCollectionViewCell else { fatalError("Expected to display a `ShowSetCollectionViewCell`.") }

        let emitter = emitters[indexPath.section]
        cell.configureWithEmitter(emitter)
    }

    override func collectionView(collectionView: UICollectionView, canFocusItemAtIndexPath indexPath: NSIndexPath) -> Bool {
        // We don't want this collectionView's cells to become focused. 
        // Instead the `UICollectionView` contained in the cell should become focused.


        let anyEmitter = emitters[indexPath.section]
        guard let _ = anyEmitter as? LocationBasedShowEmitter else { return false }

        // these handle multiple calls fine
        requestShowsAtIndex(indexPath.section)
        requestShowsAtIndex(indexPath.section + 1)

        return false
    }

    override func didUpdateFocusInContext(context: UIFocusUpdateContext, withAnimationCoordinator coordinator: UIFocusAnimationCoordinator) {

        let sameParent = context.previouslyFocusedView?.superview == context.nextFocusedView?.superview
        if sameParent { return }

        // On clicking into a show, we get one last "things have changed message"
        if let _ = context.nextFocusedView as? ImageCollectionViewCell { return }

        guard let showCell = context.nextFocusedView as? ShowCollectionViewCell else { return print("Cell needs to be ShowCollectionViewCell") }
        guard let locationCell = showCell.superview?.superview?.superview as? ShowSetCollectionViewCell else { return print("View Heriarchy has changed for the ShowSetCollectionViewCell") }

        if let indexPath = collectionView?.indexPathForCell(locationCell) {
            precacheShowImagesAtIndex(indexPath.section)
        }
    }

}
