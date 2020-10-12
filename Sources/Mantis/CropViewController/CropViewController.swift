//
//  CropViewController.swift
//  Mantis
//
//  Created by Echo on 10/30/18.
//  Copyright © 2018 Echo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import UIKit

public protocol CropViewControllerDelegate: class {
    func cropViewControllerDidCrop(_ cropViewController: CropViewController,
                                   cropped: UIImage, transformation: Transformation)
    func cropViewControllerDidFailToCrop(_ cropViewController: CropViewController, original: UIImage)
    func cropViewControllerDidCancel(_ cropViewController: CropViewController, original: UIImage)
    
    @available(*, deprecated, message: "Mantis doesn't dismiss CropViewController anymore since 1.2.0. You need to dismiss it by yourself.")
    func cropViewControllerWillDismiss(_ cropViewController: CropViewController)
}

public extension CropViewControllerDelegate where Self: UIViewController {
    func cropViewControllerDidFailToCrop(_ cropViewController: CropViewController, original: UIImage) {}
    
    @available(*, deprecated, message: "Mantis doesn't dismiss CropViewController anymore since 1.2.0. You need to dismiss it by yourself.")
    func cropViewControllerWillDismiss(_ cropViewController: CropViewController) {}
}

public enum CropViewControllerMode {
    case normal
    case customizable    
}

public class CropViewController: UIViewController {
    /// When a CropViewController is used in a storyboard,
    /// passing an image to it is needed after the CropViewController is created.
    public var image: UIImage! {
        didSet {
            cropView.image = image
        }
    }
    
    public weak var delegate: CropViewControllerDelegate?
    public var mode: CropViewControllerMode = .normal
    public var config = Mantis.Config()
    
    private var orientation: UIInterfaceOrientation = .unknown
    private lazy var cropView = CropView(image: image, viewModel: CropViewModel())
    private var cropToolbar: CropToolbarProtocol
    private var ratioPresenter: RatioPresenter?
    private var ratioSelector: RatioSelector?
    private var stackView: UIStackView?
    private var cropStackView: UIStackView!
    private var initialLayout = false
    private var disableRotation = false
    
    deinit {
        print("CropViewController deinit.")
    }
    
    init(image: UIImage,
         config: Mantis.Config = Mantis.Config(),
         mode: CropViewControllerMode = .normal,
         cropToolbar: CropToolbarProtocol = CropToolbar(frame: CGRect.zero)) {
        self.image = image
        self.config = config
        self.mode = mode
        self.cropToolbar = cropToolbar
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.cropToolbar = CropToolbar(frame: CGRect.zero)
        super.init(coder: aDecoder)
    }
    
    fileprivate func createRatioSelector() {
        let fixedRatioManager = getFixedRatioManager()
        self.ratioSelector = RatioSelector(type: fixedRatioManager.type, originalRatioH: fixedRatioManager.originalRatioH, ratios: fixedRatioManager.ratios)
        self.ratioSelector?.didGetRatio = { [weak self] ratio in
            self?.setFixedRatio(ratio)
        }
    }
    
    fileprivate func createCropToolbar() {
        cropToolbar.cropToolbarDelegate = self
        
        if case .alwaysUsingOnePresetFixedRatio(let ratio) = config.presetFixedRatioType {
            config.cropToolbarConfig.includeFixedRatioSettingButton = false
            setFixedRatio(ratio)
        } else {
            config.cropToolbarConfig.includeFixedRatioSettingButton = true
        }
        
        if mode == .normal {
            config.cropToolbarConfig.mode = .normal
        } else {
            config.cropToolbarConfig.mode = .simple
        }
        
        cropToolbar.createToolbarUI(config: config.cropToolbarConfig)
        
        cropToolbar.initConstraints(heightForVerticalOrientation: config.cropToolbarConfig.cropToolbarHeightForVertialOrientation, widthForHorizonOrientation: config.cropToolbarConfig.cropToolbarWidthForHorizontalOrientation)
    }
        
    fileprivate func getFixedRatioManager() -> FixedRatioManager {
        let type: RatioType = cropView.getRatioType(byImageIsOriginalisHorizontal: cropView.image.isHorizontal())
        
        let ratio = cropView.getImageRatioH()
        
        return FixedRatioManager(type: type,
                                 originalRatioH: ratio,
                                 ratioOptions: config.ratioOptions,
                                 customRatios: config.getCustomRatioItems())
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        createCropView()
        createCropToolbar()
        if config.cropToolbarConfig.ratioCandidatesShowType == .alwaysShowRatioList && config.cropToolbarConfig.includeFixedRatioSettingButton {
            createRatioSelector()
        }
        initLayout()
        updateLayout()
        
        NotificationCenter.default.addObserver(self, selector: #selector(rotated), name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if initialLayout == false {
            initialLayout = true
            view.layoutIfNeeded()
            cropView.adaptForCropBox()
        }
    }
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return [.top, .bottom]
    }
    
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        cropView.prepareForDeviceRotation()
    }    
    
    @objc func rotated() {
        let statusBarOrientation = UIApplication.shared.statusBarOrientation
        
        guard statusBarOrientation != .unknown else { return }
        guard statusBarOrientation != orientation else { return }
        
        orientation = statusBarOrientation
        
        if UIDevice.current.userInterfaceIdiom == .phone
            && statusBarOrientation == .portraitUpsideDown {
            return
        }
        
        updateLayout()
        view.layoutIfNeeded()
        
        // When it is embedded in a container, the timing of viewDidLayoutSubviews
        // is different with the normal mode.
        // So delay the execution to make sure handleRotate runs after the final
        // viewDidLayoutSubviews
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.cropView.handleRotate()
        }
    }

    
    func setFixedRatio(_ ratio: Double) {
        cropToolbar.handleFixedRatioSetted(ratio: ratio)
        cropView.aspectRatioLockEnabled = true
        
        if (cropView.viewModel.aspectRatio != CGFloat(ratio)) {
            cropView.viewModel.aspectRatio = CGFloat(ratio)
            
            UIView.animate(withDuration: 0.5) {
                self.cropView.setFixedRatioCropBox()
            }
        }
    }
    
    private func createCropView() {
        if !config.showRotationDial {
            cropView.angleDashboardHeight = 0
        }
        cropView.delegate = self
        cropView.clipsToBounds = true
        cropView.cropShapeType = config.cropShapeType
        cropView.cropVisualEffectType = config.cropVisualEffectType
        
        if case .alwaysUsingOnePresetFixedRatio = config.presetFixedRatioType {
            cropView.forceFixedRatio = true
        } else {
            cropView.forceFixedRatio = false
        }
    }
        
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .presetInfo(let transformInfo) = config.presetTransformationType {
            cropView.transform(byTransformInfo: transformInfo)
            return
        }
    }
    
    private func handleCancel() {
        guard config.shouldPresentCancelAlert else {
            return
        }
        let alertController = UIAlertController(title: config.cancelAlertTitle,
                                                message: config.cancelAlertMessage,
                                                preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: config.stopCancelActionTitle, style: .cancel) { _ in }
        let backAction = UIAlertAction(title: config.confirmCancelActionTitle, style: .destructive) { _ in
            self.delegate?.cropViewControllerDidCancel(self, original: self.image)
        }
        [cancelAction, backAction].forEach(alertController.addAction(_:))
        present(alertController, animated: true)
    }
    
    private func resetRatioButton() {
        cropView.aspectRatioLockEnabled = false
        cropToolbar.handleFixedRatioUnSetted()
    }
    
    @objc private func handleSetRatio() {
        if cropView.aspectRatioLockEnabled {
            resetRatioButton()
            return
        }
        
        guard let presentSourceView = cropToolbar.getRatioListPresentSourceView() else {
            return
        }
        
        let fixedRatioManager = getFixedRatioManager()
        
        guard fixedRatioManager.ratios.count > 0 else { return }
        
        if fixedRatioManager.ratios.count == 1 {
            let ratioItem = fixedRatioManager.ratios[0]
            let ratioValue = (fixedRatioManager.type == .horizontal) ? ratioItem.ratioH : ratioItem.ratioV
            setFixedRatio(ratioValue)
            return
        }
        
        ratioPresenter = RatioPresenter(type: fixedRatioManager.type, originalRatioH: fixedRatioManager.originalRatioH, ratios: fixedRatioManager.ratios)
        ratioPresenter?.didGetRatio = {[weak self] ratio in
            self?.setFixedRatio(ratio)
        }
        ratioPresenter?.present(by: self, in: presentSourceView)
    }
    
    private func handleReset() {
        resetRatioButton()
        cropView.reset()
        ratioSelector?.reset()
        ratioSelector?.update(fixedRatioManager: getFixedRatioManager())
    }
    
    private func handleRotate(rotateRadians: CGFloat) {
        var radians = cropView.forceFixedRatio ? cropView.viewModel.radians + rotateRadians : cropView.viewModel.getTotalRadians() + rotateRadians
        if radians > .pi {
            radians = -.pi + -.pi + radians
        } else if radians < -.pi {
            radians = .pi - -.pi + radians
        }
        if !disableRotation {
            disableRotation = true
            let transfromation = Transformation(
                offset: cropView.scrollView.contentOffset,
                rotation: radians,
                scale: cropView.scrollView.zoomScale,
                manualZoomed: true,
                maskFrame: cropView.gridOverlayView.frame
            )
            
            cropView.viewModel.setTouchImageStatus()
            cropView.transform(byTransformInfo: transfromation)
            cropView.viewModel.setBetweenOperationStatus()
            cropView.makeSureImageContainsCropOverlay()
            disableRotation = false
        }
    }
    
    private func handleCrop() {
        let cropResult = cropView.crop()
        guard let image = cropResult.croppedImage else {
            delegate?.cropViewControllerDidFailToCrop(self, original: cropView.image)
            return
        }

        self.delegate?.cropViewControllerDidCrop(self, cropped: image, transformation: cropResult.transformation)        
    }
    
    private func handleZoom(zoomValue: CGFloat) {
        let transfromation = Transformation(
            offset: cropView.scrollView.contentOffset,
            rotation: cropView.forceFixedRatio ? cropView.viewModel.radians : cropView.viewModel.getTotalRadians(),
            scale: zoomValue,
            manualZoomed: true,
            maskFrame: cropView.gridOverlayView.frame
        )
        
        cropView.viewModel.setTouchImageStatus()
        cropView.transform(byTransformInfo: transfromation)
        cropView.viewModel.setBetweenOperationStatus()
        cropView.makeSureImageContainsCropOverlay()
    }
}

// Auto layout
extension CropViewController {
    fileprivate func initLayout() {
        cropStackView = UIStackView()
        cropStackView.axis = .vertical
        cropStackView.addArrangedSubview(cropView)
        
        if let ratioSelector = ratioSelector {
            cropStackView.addArrangedSubview(ratioSelector)
        }
        
        stackView = UIStackView()
        view.addSubview(stackView!)
        
        cropStackView?.translatesAutoresizingMaskIntoConstraints = false
        stackView?.translatesAutoresizingMaskIntoConstraints = false
        cropToolbar.translatesAutoresizingMaskIntoConstraints = false
        cropView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView?.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        stackView?.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        stackView?.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor).isActive = true
        stackView?.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor).isActive = true
    }
    
    fileprivate func setStackViewAxis() {
        if UIApplication.shared.statusBarOrientation.isPortrait {
            stackView?.axis = .vertical
        } else if UIApplication.shared.statusBarOrientation.isLandscape {
            stackView?.axis = .horizontal
        }
    }
    
    fileprivate func changeStackViewOrder() {
        stackView?.removeArrangedSubview(cropStackView)
        stackView?.removeArrangedSubview(cropToolbar)
        
        if UIApplication.shared.statusBarOrientation.isPortrait || UIApplication.shared.statusBarOrientation == .landscapeRight {
            stackView?.addArrangedSubview(cropStackView)
            stackView?.addArrangedSubview(cropToolbar)
        } else if UIApplication.shared.statusBarOrientation == .landscapeLeft {
            stackView?.addArrangedSubview(cropToolbar)
            stackView?.addArrangedSubview(cropStackView)
        }
    }
    
    fileprivate func updateLayout() {
        setStackViewAxis()
        cropToolbar.respondToOrientationChange()
        changeStackViewOrder()
    }
}

extension CropViewController: CropViewDelegate {
    func cropViewDidBecomeResettable(_ cropView: CropView) {
        cropToolbar.handleCropViewDidBecomeResettable()
    }
    
    func cropViewDidBecomeUnResettable(_ cropView: CropView) {
        cropToolbar.handleCropViewDidBecomeUnResettable()
    }
    
    func scrollViewDidEndZooming(scale: CGFloat) {
        cropToolbar.handleScrollViewDidEndZooming(scale: scale)
    }
}

extension CropViewController: CropToolbarDelegate {
    public func didSelectCancel() {
        handleCancel()
    }
    
    public func didSelectCrop() {
        handleCrop()
    }
    
    public func didSelectCounterClockwiseRotate() {
        handleRotate(rotateRadians: -CGFloat.pi / 2)
    }

    public func didSelectClockwiseRotate() {
        handleRotate(rotateRadians: CGFloat.pi / 2)
    }
    
    public func didSelectReset() {
        handleReset()
    }
    
    public func didSelectSetRatio() {
        handleSetRatio()
    }
    
    public func didSelectRatio(ratio: Double) {
        setFixedRatio(ratio)
    }
    
    public func didChangeZoomValue(_ newValue: CGFloat) {
        handleZoom(zoomValue: newValue)
    }
}

// API
extension CropViewController {
    public func crop() {
        let cropResult = cropView.crop()
        guard let image = cropResult.croppedImage else {
            delegate?.cropViewControllerDidFailToCrop(self, original: cropView.image)
            return
        }

        delegate?.cropViewControllerDidCrop(self, cropped: image, transformation: cropResult.transformation)
    }
    
    public func process(_ image: UIImage) -> UIImage? {
        return cropView.crop(image).croppedImage
    }
}
