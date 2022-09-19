//
//  FetchedCollectionDataSource (Diffable).swift
//  AppwiseCore
//
//  Created by Jonathan Provo on 14/03/2022.
//

import CoreData
import UIKit

@available(iOS 13.0, *)
public typealias FetchedDiffableDataSource = UICollectionViewDiffableDataSource<FetchedDiffableSection, FetchedDiffableItem>

@available(iOS 13.0, *)
public final class FetchedCollectionDiffableDataSource: NSObject, NSFetchedResultsControllerDelegate {
	// MARK: - Properties
	/// A boolean indicating whether differences should be animated. The default value is `true`.
	public var isAnimatingDifferences: Bool = true

	private let controller: NSFetchedResultsController<NSFetchRequestResult>
	private let dataSource: FetchedDiffableDataSource
	private lazy var internalSnapshot: NSDiffableDataSourceSnapshot<FetchedDiffableSection, FetchedDiffableItem> = .init() // actual, non-modifiable snapshot to maintain data integrity
	private weak var delegate: FetchedCollectionDiffableDataSourceDelegate?

	// MARK: - Lifecycle

	/// Creates a diffable data source based on a `NSFetchedResultsController` instance.
	public init(controller: NSFetchedResultsController<NSFetchRequestResult>, dataSource: FetchedDiffableDataSource, delegate: FetchedCollectionDiffableDataSourceDelegate) {
		self.controller = controller
		self.dataSource = dataSource
		self.delegate = delegate
		super.init()
		commonInit()
	}

	private func commonInit() {
		setDelegate()
		performFetch()
	}

	// MARK: - Controller management

	/// Sets the delegate of the NSFetchedResultsController instance.
	private func setDelegate() {
		controller.delegate = self
	}

	/// Executes the fetch request of the NSFetchedResultsController instance.
	private func performFetch() {
		do {
			try controller.performFetch()
		} catch let error {
			assertionFailure("Error performing controller fetch: \(error)")
		}
	}

	// MARK: - NSFetchedResultsControllerDelegate

	public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
		contentWillChange()

		let snapshotWithPermanentIDs = obtainPermanentIDs(for: snapshot, in: controller.managedObjectContext)
		let typedSnapshot = snapshotWithPermanentIDs as NSDiffableDataSourceSnapshot<String, NSManagedObject>
		typedSnapshot.sectionIdentifiers.forEach { sectionIdentifier in
			let section: FetchedDiffableSection = .init(identifier: sectionIdentifier)
			internalSnapshot.deleteSections([section])
			let items: [FetchedDiffableItem] = typedSnapshot.itemIdentifiers(inSection: sectionIdentifier).map { .init(item: $0) }
			internalSnapshot.appendSections([section])
			internalSnapshot.appendItems(items, toSection: section)
		}

		var externalSnapshot = internalSnapshot // duplicate, modifiable snapshot to be displayed
		contentChangeWillBeApplied(snapshot: &externalSnapshot)

		DispatchQueue.main.async {
			// iOS bug: reloaded items are not included in the snapshot when `animatingDifferences` is `true`
			// workaround: applying the snapshot with `animatingDifferences` set to `false` reloads the items properly
			if self.isAnimatingDifferences {
				self.dataSource.apply(externalSnapshot, animatingDifferences: true) { [weak self] in
					self?.dataSource.apply(externalSnapshot, animatingDifferences: false) {
						DispatchQueue.main.async { // dispatch async required to avoid deadlock in case the delegate inititates another `apply()`
							self?.contentDidChange()
						}
					}
				}
			} else {
				self.dataSource.apply(externalSnapshot, animatingDifferences: false) { [weak self] in
					DispatchQueue.main.async { // dispatch async required to avoid deadlock in case the delegate inititates another `apply()`
						self?.contentDidChange()
					}
				}
			}
		}
	}

	// MARK: - Helpers
	/// The snapshot returned by the `NSFetchedResultsController` instance contains temporary `NSManagedObjectID`s.
	/// Working with temporary identifiers can lead to issues since at some point in time they will no longer exist.
	private func obtainPermanentIDs(for snapshot: NSDiffableDataSourceSnapshotReference, in context: NSManagedObjectContext) -> NSDiffableDataSourceSnapshotReference {
		let typedSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
		let snapshotWithPermanentIDs: NSDiffableDataSourceSnapshotReference = .init()
		typedSnapshot.sectionIdentifiers.forEach { sectionIdentifier in
			do {
				let objects = typedSnapshot.itemIdentifiers(inSection: sectionIdentifier).map { context.object(with: $0) }
				try context.obtainPermanentIDs(for: objects)
				snapshotWithPermanentIDs.appendSections(withIdentifiers: [sectionIdentifier])
				snapshotWithPermanentIDs.appendItems(withIdentifiers: objects, intoSectionWithIdentifier: sectionIdentifier)
			} catch {
				snapshotWithPermanentIDs.appendSections(withIdentifiers: [sectionIdentifier])
			}
		}
		return snapshotWithPermanentIDs
	}

	private func contentWillChange() {
		delegate?.willChangeContent()
	}

	private func contentChangeWillBeApplied(snapshot: inout NSDiffableDataSourceSnapshot<FetchedDiffableSection, FetchedDiffableItem>) {
		delegate?.contentChangeWillBeApplied(snapshot: &snapshot)
	}

	private func contentDidChange() {
		delegate?.didChangeContent()
	}
}
