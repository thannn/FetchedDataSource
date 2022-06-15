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
		var snapshot: NSDiffableDataSourceSnapshot<FetchedDiffableSection, FetchedDiffableItem> = .init()
		typedSnapshot.sectionIdentifiers.forEach { sectionIdentifier in
			let section: FetchedDiffableSection = .init(identifier: sectionIdentifier)
			let items: [FetchedDiffableItem] = typedSnapshot.itemIdentifiers(inSection: sectionIdentifier).map { .init(item: $0) }
			snapshot.appendSections([section])
			snapshot.appendItems(items, toSection: section)
		}

		// iOS bug: reloaded items are not included in the snapshot when `animatingDifferences` is `true`
		// workaround: applying the snapshot with `animatingDifferences` set to `false` reloads the items properly
		if isAnimatingDifferences {
			dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
				self?.dataSource.apply(snapshot, animatingDifferences: false) {
					self?.contentDidChange()
				}
			}
		} else {
			dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
				self?.contentDidChange()
			}
		}

		// iOS bug: `fetchLimit` is not always respected when used in `NSFetchedResultsController`
		// workaround: perform the fetch again
		if controller.fetchRequest.fetchLimit > 0 && snapshot.itemIdentifiers.count > controller.fetchRequest.fetchLimit {
			performFetch()
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
		executeOnMainThread {
			self.delegate?.willChangeContent()
		}
	}

	private func contentDidChange() {
		executeOnMainThread {
			self.delegate?.didChangeContent()
		}
	}

	private func executeOnMainThread(execute: @escaping () -> Void) {
		if Thread.current.isMainThread {
			execute()
		} else {
			DispatchQueue.main.async {
				execute()
			}
		}
	}
}
